# Regular Path Witness

Development version **0.1.0**, by [Lofrano Tecnologia](https://lofranotecnologia.com.br). Original MIT-licensed OCaml library and CLI for bounded, regular-language-constrained graph traversal. Repository: [martinlofranodeoliveira/ocaml-regular-path-witness](https://github.com/martinlofranodeoliveira/ocaml-regular-path-witness).

Given a directed multigraph, a start, explicit targets and a public expression AST, find a canonical shortest graph-edge witness. No host regex strings, network services, model dependencies, telemetry, or personal datasets. Fixtures are synthetic. This is a development tool, not a production-readiness or standards-compliance claim.

## Install and quick use

Required versions: OCaml 5.3.0, Dune 3.24.2, Yojson 3.0.0. With these already installed in an active OCaml environment:

```sh
dune build --build-dir "$PWD/build/dune" -j2 @install
dune runtest --build-dir "$PWD/build/dune" -j2
dune install --build-dir "$PWD/build/dune" --prefix "$PWD/build/install" --libdir "$PWD/build/install/lib" ocaml-regular-path-witness
build/install/bin/regular-path-witness query < examples/query.json
build/install/bin/regular-path-witness demo --assert
```

The query example returns this JSON (one line):

```json
{"status":"solved","edges":["e"],"labels":["a"],"nodes":["s","t"],"automaton":{"transition_ids":[0],"states":[0,1]},"counters":{"admitted":2,"relaxed":1,"popped":2,"membership_work":1}}
```

The demo writes an English summary to stderr and a JSON object containing all queries and outcomes to stdout. Its two solved witnesses are `["z-first","a-second"]` and `[]`; it also asserts an empty language and a deliberately exhausted budget. Redirect stdout to retain machine-readable evidence.

```ocaml
open Regular_path_witness
let q = {
  graph = { nodes = ["s"; "t"];
            edges = [{ id="e"; from_="s"; to_="t"; label="a" }] };
  start = "s"; targets = ["t"];
  regex = Concat (Epsilon, Literal "a"); budget = default_budget
}
let result = solve q
```

`Solved` carries graph vectors and an explicit accepting NFA run. `Unsat` is exhaustive. `Unknown_budget` is **not** proof of absence and never carries an uncertified incumbent. Invalid input uses the separate `Error` result. See the [precise contract](docs/contract.md), [design and proof outline](docs/design.md), and [Portuguese README](README.pt-BR.md).

## Audited offline workflow

The ordinary Dune commands above are convenient local commands, not isolation checks. The full gates require the real dependency records described in [build notes](docs/build-notes.md): a generated opam lock, official minimal repository, system artifact manifest, collected notices and measured ABI metadata. Missing or changed records fail closed. Scripts never generate or repair locks during a gate.

Preparation, with network access only for official artifacts:

```sh
python3 scripts/fetch-artifacts.py
docker build --network=none -t rpw-tools:local .
```

Use the following full isolation options for **each** invocation, in a fresh container. The only host mount is this source workspace; no home directory, credentials, agents or control sockets are passed into it.

```sh
docker run --rm --user 1000:1000 --network none --cap-drop ALL --security-opt no-new-privileges --memory 1g --cpus 2 --pids-limit 256 --tmpfs /tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000 -v "$PWD:/work" -w /work rpw-tools:local /bin/sh scripts/prepare-offline.sh
docker run --rm --user 1000:1000 --network none --cap-drop ALL --security-opt no-new-privileges --memory 1g --cpus 2 --pids-limit 256 --tmpfs /tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000 -v "$PWD:/work" -w /work rpw-tools:local /bin/sh scripts/test-offline.sh
docker run --rm --user 1000:1000 --network none --cap-drop ALL --security-opt no-new-privileges --memory 1g --cpus 2 --pids-limit 256 --tmpfs /tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000 -v "$PWD:/work" -w /work rpw-tools:local /bin/sh scripts/demo-offline.sh --assert
docker run --rm --user 1000:1000 --network none --cap-drop ALL --security-opt no-new-privileges --memory 1g --cpus 2 --pids-limit 256 --tmpfs /tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000 -v "$PWD:/work" -w /work rpw-tools:local /bin/sh scripts/package-offline.sh
```

Preparation creates only `build/` state. It requires a fresh switch and opam root rather than silently replacing existing state. The package gate builds a source archive, extracts and builds it outside the checkout, installs the library and CLI, archives/extracts the installation, and compiles an independent native consumer against that installation. It replays every solved demo witness. Package archives and their computed inventory are under `build/`.

## Why this design?

Thompson compilation makes epsilon behavior visible instead of hiding it behind a regex implementation. An indexed heap compares **complete** `(length, label vector, edge-ID vector)` keys. Local `(label, ID)` sorting is not enough: the demo explains why a larger first edge ID can still win on the complete word. The independent tiny oracle enumerates graph-edge paths and interprets AST position sets without Thompson construction.

## Limits and non-goals

Input is at most 131072 encoded bytes; ASTs have at most 64 nodes/depth 16; graphs have at most 32 nodes/128 edges. Search admits at most 4096 product pairs and attempts at most 100000 relaxations. Witnesses have at most 128 graph edges, 8192 string-payload bytes and 4096 NFA transitions. Membership and output are separately bounded. Exact details and all failure semantics are contractual, not performance measurements.

Tokens are case-sensitive ASCII `[A-Za-z0-9_.-]+`, not Unicode identifiers. There is no regex-source syntax, capture, backreference, graph editor, cancellation API or unbounded model checker. A finite stdin stream is required; a hanging producer has no application wall-clock guarantee. Bounds do not imply a general RSS, sandbox or liveness guarantee.

Security reports: [GitHub private vulnerability reporting](https://github.com/martinlofranodeoliveira/ocaml-regular-path-witness/security/advisories/new). General contact: [official homepage](https://lofranotecnologia.com.br). Dependency licenses are distinct from the original MIT implementation; see [dependency notices](docs/dependencies.md).
