# Dependency and license notices

Original Regular Path Witness logic and first-party tests/scripts are MIT, copyright 2026 Lofrano Tecnologia. This does **not** license the whole toolchain or dependency tree under MIT.

Exact runtime dependency: Yojson **3.0.0**, BSD-3-Clause, plus the OCaml **5.3.0** standard runtime/libraries. OCaml runtime licensing is **LGPL-2.1-or-later WITH OCaml-LGPL-linking-exception**; compiler/distribution components must retain their collected notices as applicable. No OCaml Str, PCRE or external graph/regex engine is used.

Build dependency: Dune **3.24.2**, MIT for Dune's own code. Bundled build-tool components retain their own terms; do not infer all Dune vendors are MIT. opam **2.3.0**, the official distribution native toolchain and Python 3 are preparation/test tools, not additional application runtime libraries. Their collected distribution and bundled-component notices remain separate.

Verified source provenance:

| Component | Official source | SHA256 |
|---|---|---|
| Dune 3.24.2 | https://github.com/ocaml/dune/releases/download/3.24.2/dune-3.24.2.tbz | 472798691b0216daf538709f0f4703b3617ef24ad0866c9096068baaba4d762a |
| Yojson 3.0.0 | https://github.com/ocaml-community/yojson/releases/download/3.0.0/yojson-3.0.0.tbz | 99414da7609b92a02474ef4b49ecda15edc8cbba5229341b124e7e4695c39610 |

The authoritative selected license texts, runtime exception, system package provenance and applicable bundled-library notices are collected in `dependency-metadata/licenses/` and covered by `dependency-metadata/inputs.sha256`. Packaging copies them unchanged into `share/ocaml-regular-path-witness/dependency-notices/`. Missing notices fail the gate; this file is an index, not a replacement for those license texts and not a compliance certification.

Official references: [OCaml manual](https://ocaml.org/manual/), [Yojson](https://github.com/ocaml-community/yojson), [Dune documentation](https://dune.readthedocs.io/), [opam manual](https://opam.ocaml.org/doc/Manual.html). Actual locks and artifact manifests, not unconstrained version ranges, govern the offline build.
