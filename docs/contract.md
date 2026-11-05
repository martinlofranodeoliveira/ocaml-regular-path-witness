# Development 0.1.0 contract / Contrato de desenvolvimento 0.1.0

## Input / Entrada

A query has exactly `graph`, `start`, `targets`, `regex`, and optionally `budget`. `graph` has exactly `nodes` (array of ID strings) and `edges` (array of objects with exactly `id`, `from`, `to`, `label`). There must be a known start, unique node IDs, unique edge IDs, known endpoints and unique, known targets. Parallel edges and self-loops are valid. An empty target set is valid. An empty node set cannot contain a valid start.

A consulta contém exatamente `graph`, `start`, `targets`, `regex` e, opcionalmente, `budget`. Nós, arestas e destinos não podem ter IDs duplicados nos respectivos conjuntos. Origem, destinos e extremos precisam existir. Arestas paralelas e laços são válidos. O conjunto de destinos pode ser vazio.

Every ID is 1–32 bytes; every label/literal is 1–16 bytes. Both use only `[A-Za-z0-9_.-]+`, case-sensitive. Numbers, Unicode identifiers, empty labels and regex-source strings are unsupported. Escaped ASCII strings such as `"\u0061"` are allowed.

IDs têm 1–32 bytes; rótulos e literais têm 1–16 bytes. A gramática é exclusivamente ASCII `[A-Za-z0-9_.-]+`, sensível a maiúsculas. Strings vazias, identificadores Unicode e regex textual não são aceitos. ASCII escapado é permitido.

| AST tag | Exact fields / Campos exatos | Language / Linguagem |
|---|---|---|
| Empty | type | no words / nenhuma palavra |
| Epsilon | type | empty word / palavra vazia |
| Literal | type, label | one whole token / um token inteiro |
| Union | type, left, right | union / união |
| Concat | type, left, right | concatenation / concatenação |
| Star | type, child | zero or more repetitions / zero ou mais repetições |

Tags have the capitalization shown. Every schema object rejects duplicate and unknown fields, including fields belonging to a different AST tag. Arrays do not accept scalars. Budget fields must be Yojson `Int`, never float or `Intlit`. A provided budget object must have both fields.

As tags usam exatamente as maiúsculas da tabela. Todos os objetos rejeitam campos desconhecidos ou duplicados, inclusive campos de outra tag AST. Arrays não aceitam escalares. Orçamentos exigem inteiros `Int`, não floats ou `Intlit`; os dois campos são obrigatórios quando o objeto existe.

Yojson performs parsing after an ASCII, quote/escape and structural-depth preflight. Raw non-ASCII bytes, raw control bytes in strings and `/` outside strings are rejected. Comments and parser extensions cannot be used to bypass the schema. This is a documented input subset, not a general JSON conformance certification.

Yojson faz o parsing após pré-validação ASCII, aspas/escapes e profundidade. Bytes não ASCII, controles crus dentro de strings e `/` fora delas são rejeitados. Não há afirmação de conformidade geral com JSON.

## Fixed bounds / Limites fixos

| Resource / Recurso | Maximum / Máximo |
|---|---:|
| Encoded query bytes / Bytes codificados | 131072 |
| JSON structural depth / Profundidade JSON | 64 |
| AST occurrences / Ocorrências AST | 64 |
| AST depth, root at 1 / Profundidade, raiz em 1 | 16 |
| Thompson states / Estados Thompson | 128 |
| Graph nodes / Nós | 32 |
| Graph edges / Arestas | 128 |
| Targets / Destinos | 32 |
| Product admissions / Admissões no produto | 4096 |
| Relaxation attempts / Tentativas de relaxação | 100000 |
| Witness graph edges / Arestas do testemunho | 128 |
| Witness string payload / Payload textual | 8192 bytes |
| Accepting NFA transitions / Transições da execução | 4096 |
| Membership work / Trabalho de pertinência | 2000000 |
| Encoded outcome / Resultado codificado | 65536 bytes |
| Tiny oracle work / Trabalho do oráculo | 2000000 |

`budget` defaults to `{"product_states":4096,"relaxations":100000}`. Configurable values range from zero to those maxima, inclusive. AST occurrences count shared subtrees once per occurrence. Depth and count guards also terminate cyclic direct OCaml ASTs. List admission walks at most limit+1 cells, so cyclic direct lists terminate too; no caller object is mutated.

`budget` usa esses máximos por padrão. Os valores configuráveis incluem zero. Subárvores compartilhadas são contadas por ocorrência. Contadores de profundidade e tamanho interrompem ASTs cíclicas; listas diretas são percorridas por no máximo limite+1 células. A entrada não é alterada.

String payload is the sum of byte lengths of every entry in `edges`, `labels` and `nodes`, counting repetitions; numeric NFA evidence is separately bounded by transition count. Membership work counts evaluator calls, position scans and queue removals in the library. The independent oracle counts its own AST operations, path checks and edge-enumeration attempts; its units are not library units or timing measurements.

Payload textual soma os bytes de todas as entradas dos três vetores, inclusive repetições. Evidência numérica tem limite separado. Trabalho de pertinência conta chamadas, varreduras de posições e remoções da fila. O oráculo tem unidades próprias; não são medições de desempenho.

## Canonical result / Resultado canônico

Rank by `(number of graph edges, complete label-token vector, complete edge-ID vector)`. Vector comparison is lexicographic over tokens, with bytewise unsigned ASCII string comparison; a string prefix sorts before its extension. Never concatenate tokens before comparison. Edge IDs only break ties after the complete word ties. Epsilon transitions consume no graph edge and add no token.

A ordem é `(quantidade de arestas, vetor completo de rótulos, vetor completo de IDs)`. Compara-se cada string por bytes ASCII e os vetores lexicograficamente. Prefixos vêm antes de suas extensões. Não concatene os tokens. IDs só desempatarão após igualdade da palavra completa. Epsilon não consome aresta nem rótulo.

Compilation allocates two states per AST occurrence, entry then exit, in preorder with the left child before the right. Transition IDs are consecutive emission-order integers starting at zero; child transitions precede enclosing transitions. Empty emits none, Epsilon/Literal emit one, Union emits entry-left, entry-right, left-exit, right-exit; Concat emits entry-left, left-right, right-exit; Star emits entry-exit, entry-child, child-loop, child-exit. States start at zero. These rules define replay evidence, not semantic rank.

A compilação aloca entrada e saída por ocorrência em pré-ordem, esquerda antes da direita. Transições recebem IDs consecutivos, a partir de zero, na ordem de emissão: filhos antes do nó externo. A ordem específica está descrita acima. Esses IDs definem a evidência, não a ordem semântica dos caminhos.

## Outcomes and counters / Resultados e contadores

`solve` returns `Error` for invalid input/construction, or an outcome. Immutable private witness/counter records can be inspected but not constructed through the public interface. Compiled data is abstract; `automaton` exposes only immutable values.

- `solved`: `edges`, `labels`, `nodes`; `automaton.transition_ids` and `automaton.states`; `counters`. Nodes include start and every subsequent endpoint. An empty witness has one graph node. NFA states have one more entry than transitions. Before success, graph and NFA replay and independent AST membership must pass.
- `unsat`: `counters`, no witness; only after exhaustive frontier completion (or validated empty targets).
- `unknown_budget`: `reason`, `counters`, no witness; a search, witness, evidence, membership or output limit blocked certification. No incumbent is returned.
- CLI `invalid`: sanitized `error`; no raw JSON echo and no witness.

`solve` distingue entrada inválida, sucesso certificado, ausência exaustiva e esgotamento. `unknown_budget` nunca significa ausência, nem retorna candidato parcial. Registros de testemunho/contadores são privados e imutáveis. Objetos compilados são abstratos.

`admitted` counts distinct product pairs, including the initial pair. `relaxed` counts each attempted epsilon transition or matching `(NFA transition, graph edge)` pair, even if it does not improve a key. `popped` counts removed heap entries. The first attempt that would exceed a configurable bound is not counted. Membership work is zero without certification; on membership exhaustion it is 2000000. Non-improving paths do not consume witness/evidence bounds. No frontier is silently truncated. Zero admissions means unknown if a nonempty-target search is needed. A valid empty target set returns unsat without search.

Os contadores têm as definições acima; não há truncamento silencioso da fronteira. Caminhos sem melhoria não gastam os limites de testemunho. Zero admissões produz unknown quando a busca é necessária; destinos vazios produzem unsat após validação.

CLI: `regular-path-witness query` consumes finite stdin and emits one newline-terminated JSON object. Exit 0 = solved, 4 = unsat, 3 = unknown_budget, 2 = invalid/usage/I/O error. `demo --assert` exits zero only when its positive and negative expectations pass. No application cancellation API or arbitrary-pipe wall-clock guarantee is provided. Tool-harness deadline failure is terminal infrastructure failure, not a query unsat.

A CLI recebe stdin finito e emite um objeto por linha; códigos: 0 sucesso, 4 ausência, 3 limite, 2 erro. Falha de prazo no harness é falha de infraestrutura, nunca ausência de caminho.
