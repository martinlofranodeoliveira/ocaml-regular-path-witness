# Design and proof outline / Projeto e esboço de prova

## Admission and compilation / Admissão e compilação

Only standard OCaml and Yojson are runtime dependencies. The parser is maintained upstream; original code handles the closed schema, bounds, graph normalization, automaton construction, search and certification. Direct API calls receive the same semantic validation as JSON. All caller-list walks are bounded before copying or sorting. Recursive AST admission checks depth before descending, which also rejects recursive OCaml values without pointer identity tricks.

State allocation reserves a fragment's entry and exit before descending left-to-right. Each AST occurrence contributes exactly two states. Empty has no connection; Epsilon has an explicit epsilon edge. Union branches and rejoins, Concat links fragments, and Star includes both an empty bypass and a child loop. Construction remains local until every bound succeeds. The compiled record is never published partially.

A validação antecede cópias, ordenação e publicação do autômato. A construção reserva dois estados por ocorrência AST e mantém epsilon explícito. Falhas não deixam objetos compilados parciais nem alteram a consulta.

## Whole-key product search / Busca com chave completa

A product pair is `(graph vertex, NFA state)`. Epsilon transitions leave the graph vertex unchanged and cost zero graph edges. A token transition follows every graph edge with that token. Each product pair stores its best complete key and one persistent accepting-run prefix. An indexed binary heap has at most one queued entry per product pair; decrease-key does not accumulate stale queue entries. Counters bound candidate attempts independently of queue occupancy.

Keys are `(edge count, token list, edge-ID list)`, not strings made by joining labels and not locally interleaved `(label, ID)` pairs. At a fixed product pair, a smaller prefix dominates a larger one: every common suffix adds the same edge count; equal-length prefix vectors preserve their lexicographic relation under appending that suffix. If counts differ, the count relation remains decisive. Future possibilities depend only on the product pair. Thus keeping one best key per pair is valid for semantic canonicality.

Along a consuming transition the count strictly increases; along epsilon the key is unchanged. Consequently a popped minimum is final. A popped accepting target is the global minimum: any strictly better accepting path would have a prefix that should already have been processed. Equal-key evidence does not affect word ranking. Ties in the heap use normalized graph index then NFA state; graph outgoing edges use sorted edge IDs and automaton outgoing transitions use stable transition IDs. Equal-key updates are ignored. This determines one accepting run independently of graph input permutation.

A menor chave por par domina as demais, pois qualquer sufixo comum preserva a ordem. Transições consumidoras aumentam a quantidade de arestas; epsilon mantém a chave. Portanto o mínimo removido da heap é definitivo. Empates semânticos mantêm a primeira evidência determinada pela ordem estável do grafo normalizado e da AST.

Nullable Star cannot create an endless equal-key loop: epsilon revisits do not strictly improve a pair. There are finitely many product pairs, and work is additionally capped. Witness/evidence bounds are checked for improving candidates. If such a candidate exceeds a bound, the search conservatively returns unknown, even if another solution might have fit. This conservatism is deliberate: evidence-budget dominance is not claimed. The engine never skips an uncertifiable improving prefix and later calls the remaining frontier exhaustive.

`Unknown_budget` é conservador: um prefixo melhor que ultrapassa limites interrompe a certificação, mesmo que outro resultado talvez coubesse. Não se presume dominância quanto ao tamanho da evidência. Isso impede afirmar ausência após descartar trabalho relevante.

## Certification and independent oracle / Certificação e oráculo

Before success, replay looks up every edge ID, checks source/destination adjacency, checks the node and label vectors, verifies final target membership, and replays all NFA transition IDs from initial to accepting state. Epsilon consumes no graph edge. A separate interpreter then checks the original AST against the finite token word. It computes reachable positions, not automaton states. For Star, a queue visits each newly reached position once, so nullable children cannot loop indefinitely. Its own work cap maps to unknown, not solved.

The tiny oracle is separate test code. It enumerates all graph-edge paths in complete edge-count layers and uses a set-transforming AST interpreter with fixed-point Star. It finishes a whole successful layer before selecting the full-vector minimum. It never calls the compiler, production membership or product search. If an accepted path exists, deleting a repeated product-pair cycle from some accepting graph/NFA run yields an accepting run with no repeated pair. Therefore a shortest witness has at most `|V| * (2 * AST occurrences) - 1` graph edges. The oracle uses this bound for exhaustive absence on tiny inputs, with a separate enumeration-work cap. Its exhaustion is `Limit`, not `Absent`.

A certificação reproduz grafo e execução NFA e verifica a AST por conjuntos finitos de posições. O oráculo independente enumera camadas completas de caminhos e interpreta a AST sem Thompson. O limite teórico acima permite provar ausência em casos pequenos; falta de trabalho do oráculo é limite, não ausência.

Tests cover the two tie-break levels separately, shorter words, token boundaries, epsilon, empty language, nullable repetition, graph permutations, parallel edges, loops, unreachable nodes, malformed/extended parser input and cyclic direct API values. Exhaustive fixtures cover 936 combinations of original tiny graphs, ASTs, starts and targets. These are behavioral checks, not performance claims.

## Owned tools and isolation / Ferramentas e isolamento

The library/CLI query path creates no subprocess. Build/package scripts need compilers and use `owned.py`. Before fixtures or fork, the launcher queries (never changes) SIGCHLD policy using the measured Linux x86-64 glibc ABI. It refuses other ABI metadata or nondefault/SA_NOCLDWAIT policy. A direct child creates a fresh session, acknowledges a private nonce, and waits for GO before exec. Only that unreaped direct-child identity authorizes signals. No PID existence probe, descendant discovery, asynchronous reaper or post-reap signal is used.

The parent observes the exact child using `waitid(P_PID, WEXITED|WNOHANG|WNOWAIT)`, retains it unreaped through TERM/KILL, and performs at most one final `waitpid`. Any wait, signal or reap error permanently disarms signals. Each stream is capped at 65536 bytes; handshake at 128 bytes; deadlines use a monotonic clock. Success needs positive EOF and a positively observed/reaped exit. An application negative exit can be checked after that normal closure.

A biblioteca não cria processos. O harness consulta SIGCHLD sem alterar a política, usa sessão reconhecida por pipe privado e mantém a identidade do filho direto sem reap até concluir todos os sinais possíveis. Erros de autoridade desarmam sinais permanentemente. Sucesso exige EOF e saída observados positivamente.

Dune 3.24.2 creates compiler process groups with setpgid. It does not escape the session in the qualified tool set, but killing the original group cannot be claimed to clean every Dune worker. Any timeout, capture failure or authority error is terminal for the outer Docker PID namespace. Scripts do not recover and launch more tools after such failure. The outer trusted harness disposes the container. Incomplete cleanup is explicit; universal termination is not promised. The wait-authority fault gate injects an error while the actual child remains unreaped, asserts zero OS signals, then exits PID 1 with 79 for namespace disposal. It must not be run as a reusable host process.

Dune cria outros grupos de processos. Matar só o grupo inicial não garante limpar todos os workers. Falhas de prazo, captura ou autoridade são terminais: o contêiner é descartado, sem descobrir PIDs nem continuar. O teste de autoridade exige PID 1 descartável e retorna 79 deliberadamente.

All offline gates require UID/GID 1000, network none, caps dropped, no-new-privileges, 1 GiB, 2 CPUs and pids256, including descendants. The trusted outer runtime establishes isolation; local checks reject obvious configuration mismatches but are not a sandbox proof. Dependencies are prepared separately from offline execution. No host home, credential or control socket is mounted. Numeric work bounds and container limits establish neither general RSS nor arbitrary-input liveness guarantees.
