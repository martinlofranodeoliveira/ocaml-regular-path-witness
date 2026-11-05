# Contributing

This is development 0.1.0. Discuss concrete defects and narrowly scoped changes through the repository's issues and pull requests. Do not submit client code, credentials, personal graph data or copied implementations. Use original synthetic fixtures.

Read `docs/contract.md` before changing behavior. The complete-vector ordering, epsilon semantics, immutable admission, exhaustive/unknown distinction and numeric limits are review requirements. A new pruning rule needs a proof or a counterexample-driven justification, not only passing examples. Do not substitute local adjacency sorting for full-key comparison.

Run the documented Dune build/test/demo commands during development. Before acceptance, use fresh containers for `scripts/test-offline.sh`, `scripts/demo-offline.sh --assert`, and `scripts/package-offline.sh` with all isolation options from the README. Also run the terminal authority-fault gate as shown in CI; expected exit is 79. Never run that fault gate in a reusable process namespace. Do not skip tests based on host detection: an unsupported environment must fail explicitly.

Dependency changes require actual official resolution, measured API/process qualification, renewed real locks, artifact hashes and complete license notices before offline checks. Do not hand-author registry metadata, fabricate hashes or regenerate a stale lock inside CI. Preserve all six shared gates listed in build notes. Do not add network runtime dependencies, telemetry, deployment or publishing workflows.

Keep changes purposeful, document failure semantics in English and Portuguese, and add regression cases that would fail an incorrect alternative implementation. Reports about security belong in private vulnerability reporting, not a public issue. Contributions to first-party code use the project's MIT license; preserve third-party notices separately.

General contact is available through https://lofranotecnologia.com.br . No response-time commitment is made.
