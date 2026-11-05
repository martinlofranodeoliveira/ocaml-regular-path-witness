# Security policy

Regular Path Witness is development version 0.1.0. No production-readiness, general sandbox or security certification is claimed.

Report vulnerabilities privately through GitHub private vulnerability reporting:

https://github.com/martinlofranodeoliveira/ocaml-regular-path-witness/security/advisories/new

Include a minimal synthetic reproducer, toolchain versions, the violated contract, expected/observed result and whether resource exhaustion or incomplete cleanup occurred. Do not include secrets, real personal data or private client graphs. Do not publish exploit details in ordinary issues before private review. No response-time SLA is offered. General contact: https://lofranotecnologia.com.br .

The query API is pure with respect to caller inputs and creates no processes or network connections. It imposes byte, depth, graph, AST, search, evidence and verification bounds. These limits do not guarantee a fixed RSS or termination against a hanging stdin producer. Consumers must distinguish invalid input, exhaustive absence and unknown budget.

Build/package tooling executes fixed compilers through an acknowledged owned-child launcher. Its supported ABI is checked explicitly. Dune may create separate process groups, so timeout or authority failure can leave cleanup incomplete; the outer disposable container must be terminated. Never reuse that namespace after a terminal gate failure. Do not mount home directories, credentials, agent sockets or Docker/control sockets into a gate. Do not grant mount capability to tests. Use only the read-only dependency artifacts and owned synthetic scratch storage documented in build notes.

Package extraction rejects absolute/traversing paths, duplicate members, links and special files and has file/byte bounds. It is deliberately not a general archive extraction service. Artifact checksums detect drift relative to trusted preparation records; they are not a substitute for authentic upstream provenance or review.
