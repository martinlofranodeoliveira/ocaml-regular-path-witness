"""Strict consumers of real preparation data; no lock generation or repair."""
import hashlib
import json
import os
import re
from pathlib import Path, PurePosixPath

CLOSURE = {
    "base-bigarray": "base", "base-domains": "base", "base-effects": "base",
    "base-nnp": "base", "base-threads": "base", "base-unix": "base",
    "dune": "3.24.2", "ocaml": "5.3.0", "ocaml-config": "3",
    "ocaml-system": "5.3.0", "yojson": "3.0.0",
}
SOURCES = {
    "https://github.com/ocaml/dune/releases/download/3.24.2/dune-3.24.2.tbz":
        "472798691b0216daf538709f0f4703b3617ef24ad0866c9096068baaba4d762a",
    "https://github.com/ocaml-community/yojson/releases/download/3.0.0/yojson-3.0.0.tbz":
        "99414da7609b92a02474ef4b49ecda15edc8cbba5229341b124e7e4695c39610",
    'https://raw.githubusercontent.com/ocaml/ocaml/66f33f6e08857f3c3cb53fc1759fbad6860c59bd/tools/opam/gen_ocaml_config.ml.in':
        'a9ad8d84a08961159653a978db92d10f694510182b206cacb96d5c9f63b5121e',
    'https://raw.githubusercontent.com/ocaml/ocaml/363fb9f5a2fb87dbd5f8cc579af87dd04e14343b/tools/opam/ocaml-config.install':
        '6e4fd93f4cce6bad0ed3c08afd0248dbe7d7817109281de6294e5b5ef5597051',
    'https://raw.githubusercontent.com/ocaml/ocaml/bcb802e851a1391ac6fff957d63b0edbf849225a/tools/opam/gen_ocaml-system_config.ml.in':
        '71bcd3d35e28cbf71eda81991c8741268f4b87ced71573b2e75f64f136cebfc1',
}


def relative(value):
    p = PurePosixPath(value)
    if (not value or p.is_absolute() or any(x in (".", "..") for x in value.split("/"))
            or "\\" in value or "\n" in value or "\r" in value):
        raise ValueError("unsafe metadata path")
    return Path(*p.parts)


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def artifacts(root):
    data = json.loads((root / "dependency-metadata/artifacts.json").read_text())
    if set(data) != {"format", "artifacts"} or data["format"] != 1:
        raise ValueError("artifact manifest schema")
    if not 2 <= len(data["artifacts"]) <= 512:
        raise ValueError("artifact count")
    seen = set()
    sources = {}
    for item in data["artifacts"]:
        if set(item) != {"path", "url", "sha256", "kind"}:
            raise ValueError("artifact entry schema")
        path = relative(item["path"])
        if str(path) in seen or not re.fullmatch("[0-9a-f]{64}", item["sha256"]):
            raise ValueError("duplicate artifact or invalid digest")
        seen.add(str(path))
        if item["kind"] == "source":
            if path.parts[0] != "sources" or item["url"] in sources:
                raise ValueError("source path/identity")
            sources[item["url"]] = item["sha256"]
        elif item["kind"] == "deb":
            if len(path.parts) != 2 or path.parts[0] != "debs" or path.suffix != ".deb":
                raise ValueError("system artifact path")
        else:
            raise ValueError("artifact kind")
    if sources != SOURCES:
        raise ValueError("qualified source set drift")
    return data["artifacts"]


def verify(root, artifact_root=None):
    metadata = root / "dependency-metadata"
    lock = root / "ocaml-regular-path-witness.opam.locked"
    if not lock.is_file():
        raise ValueError("real opam lock is required")
    manifest = metadata / "inputs.sha256"
    seen = set()
    for line in manifest.read_text().splitlines():
        if not re.fullmatch(r"[0-9a-f]{64}  [^\r\n]+", line):
            raise ValueError("input digest syntax")
        sha, name = line.split("  ", 1)
        path = root / relative(name)
        if name in seen or path.is_symlink() or not path.is_file() or digest(path) != sha:
            raise ValueError("input metadata drift")
        seen.add(name)
    required = {"ocaml-regular-path-witness.opam", "ocaml-regular-path-witness.opam.locked",
                "dependency-metadata/artifacts.json", "dependency-metadata/platform.json",
                "dependency-metadata/system-packages.json",
                "dependency-metadata/opam-repository/repo"}
    for path in (metadata / "opam-repository").rglob("*"):
        if path.is_file():
            required.add(path.relative_to(root).as_posix())
    notices = metadata / "licenses"
    if not notices.is_dir() or not any(notices.iterdir()):
        raise ValueError("collected license texts are required")
    for path in notices.rglob("*"):
        if path.is_file():
            required.add(path.relative_to(root).as_posix())
    if not required <= seen:
        raise ValueError("uncovered dependency metadata")
    items = artifacts(root)
    if artifact_root is not None:
        for item in items:
            path = artifact_root / relative(item["path"])
            if path.is_symlink() or digest(path) != item["sha256"]:
                raise ValueError("artifact digest mismatch")
    return items


def require_gate():
    if os.getuid() != 1000 or os.getgid() != 1000:
        raise ValueError("offline gate requires UID/GID 1000")
    status = {}
    for line in Path("/proc/self/status").read_text().splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            status[k] = v.strip()
    if int(status["CapEff"], 16) != 0 or status["NoNewPrivs"] != "1":
        raise ValueError("offline gate requires caps0 and no-new-privileges")
    if set(os.listdir("/sys/class/net")) != {"lo"}:
        raise ValueError("offline gate requires an isolated network namespace")
    cg = Path("/sys/fs/cgroup")
    if (cg / "memory.max").read_text().strip() != "1073741824":
        raise ValueError("offline memory gate")
    if (cg / "pids.max").read_text().strip() != "256":
        raise ValueError("offline PID gate")
    quota, period = (cg / "cpu.max").read_text().split()
    if quota == "max" or int(quota) != 2 * int(period):
        raise ValueError("offline CPU gate")
