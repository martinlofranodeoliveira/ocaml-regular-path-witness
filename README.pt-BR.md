# Regular Path Witness

Versão de desenvolvimento **0.1.0**, da [Lofrano Tecnologia](https://lofranotecnologia.com.br). Biblioteca e CLI originais em OCaml, sob MIT, para caminhos em grafos sujeitos a uma linguagem regular. [Repositório](https://github.com/martinlofranodeoliveira/ocaml-regular-path-witness).

Recebe multigrafo direcionado, origem, conjunto explícito de destinos e AST pública. Encontra um testemunho mínimo canônico. Não usa expressões regex do sistema, modelos, APIs externas, telemetria nem dados pessoais. Todos os exemplos são sintéticos. Não há afirmação de prontidão para produção ou conformidade ampla com padrões.

## Instalação e uso

Versões exigidas: OCaml 5.3.0, Dune 3.24.2 e Yojson 3.0.0, já instalados no ambiente OCaml ativo:

```sh
dune build --build-dir "$PWD/build/dune" -j2 @install
dune runtest --build-dir "$PWD/build/dune" -j2
dune install --build-dir "$PWD/build/dune" --prefix "$PWD/build/install" --libdir "$PWD/build/install/lib" ocaml-regular-path-witness
build/install/bin/regular-path-witness query < examples/query.json
build/install/bin/regular-path-witness demo --assert
```

Saída exata do exemplo, em uma linha:

```json
{"status":"solved","edges":["e"],"labels":["a"],"nodes":["s","t"],"automaton":{"transition_ids":[0],"states":[0,1]},"counters":{"admitted":2,"relaxed":1,"popped":2,"membership_work":1}}
```

O demo escreve resumo legível em inglês no stderr e um objeto JSON com consultas e resultados no stdout. Os testemunhos positivos são `["z-first","a-second"]` e `[]`. Também verifica uma linguagem vazia e um orçamento deliberadamente insuficiente.

```ocaml
open Regular_path_witness
let q = {
  graph = { nodes=["s";"t"];
            edges=[{id="e";from_="s";to_="t";label="a"}] };
  start="s"; targets=["t"];
  regex=Concat(Epsilon,Literal "a"); budget=default_budget
}
let result = solve q
```

## AST e busca

`Empty` representa a linguagem vazia; `Epsilon`, a palavra vazia; `Literal`, um token inteiro. `Union`, `Concat` e `Star` têm a semântica usual de união, concatenação e repetição finita. Em JSON, use `type`, `label`, `left`, `right` e `child` conforme o [contrato bilíngue](docs/contract.md). Não existe parser de strings regex.

A construção de Thompson expõe transições epsilon de custo zero. A busca no produto grafo × autômato compara primeiro a quantidade de arestas, depois **todo** o vetor de tokens e finalmente **todo** o vetor de IDs das arestas, em ordem ASCII por bytes. Ordenar apenas as saídas locais não resolve esse desempate. `Star` anulável termina porque chaves iguais não são relaxadas novamente.

`Solved` inclui caminho reproduzível e execução aceitante do autômato; há verificação de adjacência, destinos, rótulos e pertinência à AST original. `Unsat` significa ausência exaustiva dentro de uma busca concluída. `Unknown_budget` significa que um limite impediu a conclusão: **não** é prova de ausência. Entrada inválida é `Error`, sem testemunho parcial. A entrada não é alterada em falhas ou esgotamento.

## Gates offline e pacote instalado

Os comandos Dune são úteis localmente, mas não substituem isolamento. Os [registros de preparação](docs/build-notes.md) exigem lock opam real, repositório mínimo oficial, artefatos com hashes reais, licenças coletadas e metadados da ABI. A falta ou alteração desses registros causa falha explícita. Não há reparo automático de locks.

Preparação de artefatos oficiais, com rede:

```sh
python3 scripts/fetch-artifacts.py
docker build --network=none -t rpw-tools:local .
```

Cada comando abaixo usa um contêiner novo. Somente o diretório fonte é montado; não monte home, credenciais, agentes ou sockets de controle.

```sh
docker run --rm --user 1000:1000 --network none --cap-drop ALL --security-opt no-new-privileges --memory 1g --cpus 2 --pids-limit 256 --tmpfs /tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000 -v "$PWD:/work" -w /work rpw-tools:local /bin/sh scripts/prepare-offline.sh
docker run --rm --user 1000:1000 --network none --cap-drop ALL --security-opt no-new-privileges --memory 1g --cpus 2 --pids-limit 256 --tmpfs /tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000 -v "$PWD:/work" -w /work rpw-tools:local /bin/sh scripts/test-offline.sh
docker run --rm --user 1000:1000 --network none --cap-drop ALL --security-opt no-new-privileges --memory 1g --cpus 2 --pids-limit 256 --tmpfs /tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000 -v "$PWD:/work" -w /work rpw-tools:local /bin/sh scripts/demo-offline.sh --assert
docker run --rm --user 1000:1000 --network none --cap-drop ALL --security-opt no-new-privileges --memory 1g --cpus 2 --pids-limit 256 --tmpfs /tmp:rw,exec,nosuid,nodev,size=256m,uid=1000,gid=1000 -v "$PWD:/work" -w /work rpw-tools:local /bin/sh scripts/package-offline.sh
```

A restauração exige estado novo em `build/`. O gate de pacote cria arquivo fonte, extrai e compila fora do checkout, instala, empacota e extrai a instalação. Um consumidor OCaml independente é compilado contra a biblioteca instalada e reproduz todos os testemunhos positivos do demo. Arquivos e inventário calculado ficam em `build/`.

## Limitações

JSON: 131072 bytes e profundidade estrutural 64. AST: 64 nós e profundidade 16. Grafo: 32 nós e 128 arestas. Tokens ASCII sensíveis a maiúsculas; IDs de 1–32 bytes e rótulos de 1–16 bytes. Produto: até 4096 pares; relaxações: até 100000. Testemunho: até 128 arestas, 8192 bytes de payload textual e 4096 transições NFA. Verificação de pertinência: 2000000 unidades de trabalho; relatório: 65536 bytes.

Não há capturas, referências retroativas, editor gráfico, cancelamento nem verificador ilimitado. Stdin deve ser um fluxo finito; um produtor bloqueado não tem prazo garantido pela aplicação. Os contadores não garantem RSS, sandbox ou término universal. O [projeto](docs/design.md) explica as provas e a limpeza incompleta possível das ferramentas de build.

Segurança: [relato privado no GitHub](https://github.com/martinlofranodeoliveira/ocaml-regular-path-witness/security/advisories/new). Contato geral: [site oficial](https://lofranotecnologia.com.br). As dependências mantêm licenças próprias, descritas em [dependências](docs/dependencies.md).
