open Regular_path_witness
let checks = ref 0
let check message condition = incr checks; if not condition then failwith message
let ok = function Ok x -> x | Error e -> failwith (error_message e)
let edge id from_ to_ label = {id;from_;to_;label}
let query ?(start="s") ?(targets=["t"]) ?(budget=default_budget) nodes edges regex =
  { graph={nodes;edges};start;targets;regex;budget }
let solved q expected =
  match ok (solve q) with
  | Solved (w,_) ->
    check "canonical edges" (w.edges = expected);
    check "replay certification" (check_witness q w = Ok ()); w
  | _ -> failwith "expected solved"
let is_unknown = function Ok (Unknown_budget _) -> true | _ -> false
let rejected = function Error _ -> true | _ -> false
let same_as_oracle q =
  match Oracle.decide q, ok (solve q) with
  | Oracle.Found ids, Solved (w,_) ->
    check "oracle key disagreement" (ids=w.edges);
    check "oracle replay" (check_witness q w=Ok ())
  | Oracle.Absent, Unsat _ -> check "oracle exhaustive absence" true
  | Oracle.Limit, _ -> failwith "tiny oracle exceeded its own work bound"
  | _ -> failwith "oracle existence disagreement"
let () =
  let a = Literal "a" and b = Literal "b" in
  let base = query ~targets:["s"] ["s"] [] Epsilon in
  ignore (solved base []);
  check "empty language differs from epsilon" (match ok (solve {base with regex=Empty}) with Unsat _ -> true | _ -> false);
  let nullable = {base with graph={nodes=["s"];edges=[edge "loop" "s" "s" "a"]};
    regex=Star (Union (Epsilon,a))} in
  same_as_oracle nullable;
  check "nullable membership" (ok (accepts nullable.regex ["a";"a";"a"]));
  check "nullable nonmember" (not (ok (accepts nullable.regex ["b"])));
  let branching = query ["s";"u";"v";"t"]
    [edge "a-first" "s" "u" "a";edge "z-second" "u" "t" "b";
     edge "z-first" "s" "v" "a";edge "a-second" "v" "t" "a"]
    (Concat(a,Union(a,b))) in
  let w = solved branching ["z-first";"a-second"] in
  let reversed = {branching with graph={nodes=List.rev branching.graph.nodes;
                                       edges=List.rev branching.graph.edges}} in
  let wr = solved reversed w.edges in
  check "input permutations preserve evidence" (w.transition_ids=wr.transition_ids && w.nfa_states=wr.nfa_states);
  same_as_oracle branching;
  let parallel = query ["s";"t"] [edge "e2" "s" "t" "a";edge "e10" "s" "t" "a"] a in
  ignore (solved parallel ["e10"]); same_as_oracle parallel;
  let full_ids = query ["s";"u";"v";"t"]
    [edge "b" "s" "u" "a";edge "a" "u" "t" "a";
     edge "a0" "s" "v" "a";edge "z" "v" "t" "a"] (Concat(a,a)) in
  ignore (solved full_ids ["a0";"z"]); same_as_oracle full_ids;
  let short = query ["s";"u";"t"]
    [edge "z" "s" "t" "z";edge "a" "s" "u" "a";edge "b" "u" "t" "b"]
    (Union(Literal "z",Concat(a,b))) in
  ignore (solved short ["z"]); same_as_oracle short;
  let tokens = query ["s";"u";"v";"t"]
    [edge "z1" "s" "u" "a";edge "z2" "u" "t" "bb";
     edge "a1" "s" "v" "aa";edge "a2" "v" "t" "a"]
    (Union(Concat(a,Literal "bb"),Concat(Literal "aa",a))) in
  ignore (solved tokens ["z1";"z2"]); same_as_oracle tokens;
  let unreachable = query ["s";"t";"unused"] [edge "self" "s" "s" "a"] (Concat(a,b)) in
  same_as_oracle unreachable;
  check "zero product is unknown" (is_unknown (solve {base with budget={default_budget with product_states=0}}));
  check "zero relaxations is unknown" (is_unknown (solve {base with budget={default_budget with relaxations=0}}));
  check "one admission is insufficient for epsilon" (is_unknown (solve {base with budget={default_budget with product_states=1}}));
  check "empty targets validated but no search needed"
    (match ok (solve {base with targets=[];budget={product_states=0;relaxations=0}}) with Unsat c -> c.admitted=0 | _ -> false);
  let original = branching in
  ignore (solve {branching with budget={product_states=1;relaxations=1}});
  check "input not mutated" (branching=original);
  check "duplicate edge" (rejected (solve {parallel with graph={parallel.graph with edges=List.hd parallel.graph.edges :: parallel.graph.edges}}));
  check "unknown endpoint" (rejected (solve (query ["s";"t"] [edge "e" "s" "x" "a"] a)));
  check "duplicate target" (rejected (solve {base with targets=["s";"s"]}));
  check "invalid ASCII token" (rejected (solve {base with regex=Literal "a b"}));
  let rec deep n r = if n=0 then r else deep (n-1) (Star r) in
  check "depth 16 admitted" (match compile (deep 15 Epsilon) with Ok _ -> true | _ -> false);
  check "depth 17 rejected" (rejected (compile (deep 16 Epsilon)));
  let rec cyclic_ast = Star cyclic_ast in
  check "cyclic AST bounded" (rejected (compile cyclic_ast));
  let rec cyclic_nodes = "s" :: cyclic_nodes in
  check "cyclic graph list bounded" (rejected (solve {base with graph={nodes=cyclic_nodes;edges=[]}}));
  let rec cyclic_edges = edge "e" "s" "s" "a" :: cyclic_edges in
  check "cyclic edge list bounded" (rejected (solve {base with graph={nodes=["s"];edges=cyclic_edges}}));
  let rec cyclic_targets = "s" :: cyclic_targets in
  check "cyclic target list bounded" (rejected (solve {base with targets=cyclic_targets}));
  let rec tree depth = if depth=0 then Epsilon else Union(tree (depth-1),tree (depth-1)) in
  let c = ok (compile (Star (tree 5))) in
  check "64 AST nodes yield 128 NFA states" ((automaton c).state_count=128);
  check "65 AST nodes rejected" (rejected (compile (Union(Epsilon,Star(tree 5)))));
  let json = "{\"graph\":{\"nodes\":[\"s\"],\"edges\":[]},\"start\":\"s\",\"targets\":[\"s\"],\"regex\":{\"type\":\"Epsilon\"}}" in
  ignore (solved (ok (decode json)) []);
  let malformed = ["";"{";json ^ " {}";"/*comment*/" ^ json;
    "{\"graph\":{},\"graph\":{}}";
    "{\"graph\":{\"nodes\":[\"s\"],\"edges\":[],\"x\":0},\"start\":\"s\",\"targets\":[],\"regex\":{\"type\":\"Empty\"}}";
    "{\"graph\":{\"nodes\":[\"s\"],\"edges\":[]},\"start\":\"s\",\"targets\":[],\"regex\":{\"type\":\"Empty\",\"type\":\"Empty\"}}";
    "{\"graph\":{\"nodes\":[\"s\"],\"edges\":[]},\"start\":\"s\",\"targets\":[],\"regex\":{\"type\":\"Empty\",\"label\":\"a\"}}";
    String.make 131073 ' '; "\255";
    String.make 65 '[' ^ String.make 65 ']'] in
  List.iter (fun text -> check "malformed/extended JSON rejected" (rejected (decode text))) malformed;
  List.iter (fun number ->
    let text = String.sub json 0 (String.length json-1) ^
      ",\"budget\":{\"product_states\":" ^ number ^ ",\"relaxations\":1}}" in
    check "noninteger budget rejected" (rejected (decode text)))
    ["NaN";"Infinity";"1.0";"999999999999999999999999999999";"-1";"4097"];
  let escaped = "{\"graph\":{\"nodes\":[\"\\u0073\"],\"edges\":[]},\"start\":\"s\",\"targets\":[\"s\"],\"regex\":{\"type\":\"Epsilon\"}}" in
  ignore (solved (ok (decode escaped)) []);
  let escaped_bad = "{\"graph\":{\"nodes\":[\"\\u00e9\"],\"edges\":[]},\"start\":\"s\",\"targets\":[],\"regex\":{\"type\":\"Empty\"}}" in
  check "decoded nonASCII rejected" (rejected (decode escaped_bad));
  (* Exhaustive original fixture family: 9 graphs, 13 ASTs, 2 starts,
     4 target sets. Repeated labels, self-loops and unreachable nodes included. *)
  let graphs = [] :: List.concat_map (fun source ->
    List.concat_map (fun destination -> List.map (fun label ->
      [edge "e" source destination label]) ["a";"b"]) ["s";"t"]) ["s";"t"] in
  let asts = [Empty;Epsilon;a;b;Union(a,b);Concat(a,b);Concat(a,a);
              Star a;Star Epsilon;Star Empty;Star(Union(Epsilon,a));
              Concat(Star a,b);Union(Epsilon,Concat(b,a))] in
  List.iter (fun edges -> List.iter (fun regex ->
    List.iter (fun start -> List.iter (fun targets ->
      same_as_oracle (query ~start ~targets ["s";"t"] edges regex))
      [[];["s"];["t"];["s";"t"]]) ["s";"t"]) asts) graphs;
  check "oracle budget is not absence" (Oracle.decide ~maximum_work:0 branching = Oracle.Limit);
  Printf.printf "regular-path-witness: %d behavioral checks passed\n" !checks
