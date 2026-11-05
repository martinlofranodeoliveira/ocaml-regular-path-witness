"""Offline build, demo and package gates. All tool launches use owned.run."""
import hashlib
import json
import os
import shutil
import sys
import tarfile
import tempfile
from pathlib import Path
from metadata import CLOSURE, verify, relative, require_gate
from owned import run, authority_fault, check_policy

ROOT = Path(__file__).resolve().parents[1]
PLATFORM = ROOT / "dependency-metadata/platform.json"
BUILD = ROOT / "build"
ENV = os.environ.copy()
ENV.update({"OPAMROOT": str(BUILD / "opam-root"), "OPAMNOAUTOUPDATE": "1",
            "OPAMYES": "1", "OPAMJOBS": "2", "OPAMDOWNLOADJOBS": "1",
            "OPAMRETRIES": "0", "OPAMFETCH": "/bin/false", "DUNE_CACHE": "disabled",
            "PYTHONDONTWRITEBYTECODE": "1"})
SWITCH = BUILD / "ocaml-switch"


def tool(argv, *, cwd=ROOT, input_data=b"", expected=(0,), timeout=300, echo=True):
    result = run([str(x) for x in argv], metadata=PLATFORM, cwd=str(cwd), env=ENV,
                 input_data=input_data, timeout=timeout)
    if echo:
        sys.stdout.buffer.write(result.stdout)
        sys.stderr.buffer.write(result.stderr)
        sys.stdout.flush()
        sys.stderr.flush()
    if result.code not in expected:
        raise RuntimeError("tool exited with status " + str(result.code))
    return result


def closure():
    result = tool(["opam", "list", "--switch=" + str(SWITCH), "--installed",
                   "--columns=name,version", "--color=never"], echo=False)
    actual = {}
    for line in result.stdout.decode().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 2 or fields[0] in actual:
            raise ValueError("opam closure output")
        actual[fields[0]] = fields[1]
    if actual != CLOSURE:
        raise ValueError("installed closure drift")


def configure():
    prefix = Path(tool(["opam", "var", "--switch=" + str(SWITCH), "prefix"],
                       echo=False).stdout.decode().strip())
    if not prefix.is_absolute() or not prefix.is_dir():
        raise ValueError("switch prefix")
    ENV["PATH"] = str(prefix / "bin") + os.pathsep + os.environ["PATH"]
    ENV["OCAMLPATH"] = str(prefix / "lib")
    ENV["CAML_LD_LIBRARY_PATH"] = str(prefix / "lib/stublibs")
    ENV["OPAMSWITCH"] = str(SWITCH)
    closure()
    if tool(["ocamlc", "-version"], echo=False).stdout.strip() != b"5.3.0":
        raise ValueError("compiler drift")
    if tool(["dune", "--version"], echo=False).stdout.strip() != b"3.24.2":
        raise ValueError("Dune drift")
    return prefix


def prepare(items, artifacts):
    if (BUILD / "opam-root").exists() or SWITCH.exists():
        raise ValueError("preparation requires a fresh owned build directory")
    cache = BUILD / "opam-root/download-cache/sha256"
    for item in items:
        if item["kind"] == "source":
            destination = cache / item["sha256"][:2] / item["sha256"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(artifacts / relative(item["path"]), destination)
    tool(["opam", "init", "--bare", "--disable-sandboxing", "--no-setup", "--yes",
          "--kind=local", "qualified", ROOT / "dependency-metadata/opam-repository"], timeout=180)
    tool(["opam", "switch", "create", SWITCH, "ocaml-system.5.3.0", "--yes",
          "--no-install"], timeout=180)
    tool(["opam", "install", "--switch=" + str(SWITCH), "--yes", "--no-depexts",
          "--deps-only", "--locked", ROOT / "ocaml-regular-path-witness.opam"], timeout=600)
    configure()
    print("Offline switch restored and exact eleven-package closure verified.")


def dune_build(root, build_dir, *targets):
    build_dir.parent.mkdir(parents=True, exist_ok=True)
    tool(["dune", "build", "--root", root, "--build-dir", build_dir, "-j2", *targets])


def archive(source, destination):
    paths = []
    total = 0
    for base, dirs, files in os.walk(source, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in {".git", "build", "_build", "__pycache__"})
        for d in dirs:
            if (Path(base) / d).is_symlink():
                raise ValueError("package directory symlink")
        for name in sorted(files):
            path = Path(base) / name
            if path.is_symlink() or not path.is_file():
                raise ValueError("package special file")
            size = path.stat().st_size
            total += size
            paths.append(path)
            if size > 33554432 or total > 67108864 or len(paths) > 4096:
                raise ValueError("package bounds")
    with tarfile.open(destination, "w", format=tarfile.USTAR_FORMAT) as output:
        for path in sorted(paths):
            info = output.gettarinfo(str(path), path.relative_to(source).as_posix())
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = 0
            info.mode = 0o644
            with path.open("rb") as stream:
                output.addfile(info, stream)
    if destination.stat().st_size > 68157440:
        raise ValueError("encoded archive bound")
    return paths


def extract(archive_path, destination):
    seen = set()
    total = 0
    with tarfile.open(archive_path, "r:") as source:
        for count, info in enumerate(source):
            if count >= 4096 or not info.isfile() or info.size > 33554432:
                raise ValueError("archive entry bound/type")
            name = str(relative(info.name))
            if name in seen:
                raise ValueError("duplicate archive entry")
            seen.add(name)
            total += info.size
            if total > 67108864:
                raise ValueError("extracted package bound")
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            stream = source.extractfile(info)
            if stream is None:
                raise ValueError("missing archive body")
            with path.open("xb") as output:
                shutil.copyfileobj(stream, output, 65536)
            path.chmod(0o644)


def package(prefix):
    source_tar = BUILD / "regular-path-witness-0.1.0-source.tar"
    archive(ROOT, source_tar)
    with tempfile.TemporaryDirectory(prefix="rpw-package-") as temporary:
        scratch = Path(temporary)
        source = scratch / "source"
        source.mkdir()
        extract(source_tar, source)
        verify(source)
        build_dir = scratch / "build/dune"
        dune_build(source, build_dir, "@install", "@runtest")
        stage = scratch / "stage"
        tool(["dune", "install", "--root", source, "--build-dir", build_dir,
              "--prefix", stage, "--libdir", stage / "lib", "ocaml-regular-path-witness"], cwd=source)
        notices = stage / "share/ocaml-regular-path-witness/dependency-notices"
        shutil.copytree(source / "dependency-metadata/licenses", notices)
        shutil.copyfile(source_tar, stage / "share/ocaml-regular-path-witness/source.tar")
        installed_tar = BUILD / "regular-path-witness-0.1.0-installed.tar"
        paths = archive(stage, installed_tar)
        inventory = [{"path": p.relative_to(stage).as_posix(),
                      "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]
        (BUILD / "package-inventory.json").write_text(json.dumps(inventory, sort_keys=True) + "\n")
        installed = scratch / "installed"
        installed.mkdir()
        extract(installed_tar, installed)
        cli = installed / "bin/regular-path-witness"
        cli.chmod(0o755)
        demo = tool([cli, "demo", "--assert"], cwd=scratch, echo=False)
        (scratch / "demo.json").write_bytes(demo.stdout)
        sys.stdout.buffer.write(demo.stdout)
        sys.stderr.buffer.write(demo.stderr)
        share = installed / "share/ocaml-regular-path-witness"
        result = tool([cli, "query"], cwd=scratch, input_data=(share / "query.json").read_bytes(), echo=False)
        if json.loads(result.stdout)["edges"] != ["e"]:
            raise ValueError("installed query contract")
        consumer = scratch / "consumer.ml"
        shutil.copyfile(share / "consumer.ml", consumer)
        library = installed / "lib/ocaml-regular-path-witness"
        for name in ("regular_path_witness.cmi", "regular_path_witness.cmxa", "regular_path_witness.a"):
            if not (library / name).is_file():
                raise ValueError("installed native library inventory")
        tool(["ocamlopt", "-I", library, "-I", prefix / "lib/yojson", "yojson.cmxa",
              "regular_path_witness.cmxa", consumer, "-o", scratch / "consumer"], cwd=scratch)
        tool([scratch / "consumer", scratch / "demo.json"], cwd=scratch)
    print("Source archive, extracted build, installed CLI and independent installed consumer passed.")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {"prepare", "test", "demo", "package", "authority-fault"}:
        raise ValueError("gate command")
    require_gate()
    check_policy(PLATFORM)
    items = verify(ROOT)
    if sys.argv[1] == "authority-fault":
        authority_fault(PLATFORM)
    BUILD.mkdir(exist_ok=True)
    if sys.argv[1] == "prepare":
        artifacts = Path(os.environ.get("RPW_ARTIFACTS", "/opt/artifacts"))
        verify(ROOT, artifacts)
        prepare(items, artifacts)
        return
    prefix = configure()
    build_dir = BUILD / "dune"
    if sys.argv[1] == "test":
        tool([sys.executable, ROOT / "scripts/test-owned-admission.py"], timeout=30)
        dune_build(ROOT, build_dir, "@runtest", "bin/main.exe")
        cli = build_dir / "default/bin/main.exe"
        for text, code, status in [(b"{}", 2, "invalid"),
                                   ((ROOT / "examples/query.json").read_bytes(), 0, "solved")]:
            result = tool([cli, "query"], input_data=text, expected=(code,), echo=False)
            if json.loads(result.stdout)["status"] != status:
                raise ValueError("CLI status regression")
    elif sys.argv[1] == "demo":
        dune_build(ROOT, build_dir, "bin/main.exe")
        tool([build_dir / "default/bin/main.exe", "demo", "--assert"])
    else:
        package(prefix)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("OFFLINE GATE FAILED (terminal; dispose container): " + str(exc), file=sys.stderr, flush=True)
        sys.exit(1)
