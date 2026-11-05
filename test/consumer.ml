(* Compiled again against only the installed library, outside the source tree. *)
open Regular_path_witness
let fail message = failwith ("installed consumer: " ^ message)
let member name = function
  | `Assoc fields -> (match List.assoc_opt name fields with Some x -> x | None -> fail "field")
  | _ -> fail "object"
let string = function `String s -> s | _ -> fail "string"
let list = function `List xs -> xs | _ -> fail "list"
let integer = function `Int n -> n | _ -> fail "integer"
let ok = function Ok x -> x | Error _ -> fail "library rejection"
let () =
  if Array.length Sys.argv <> 2 then fail "expected demo report filename";
  let channel = open_in_bin Sys.argv.(1) in
  let length = in_channel_length channel in
  if length > 65536 then fail "report bound";
  let text = really_input_string channel length in close_in channel;
  let cases = list (member "cases" (Yojson.Safe.from_string text)) in
  let solved = ref 0 in
  List.iter (fun case ->
    let q = ok (decode (Yojson.Safe.to_string (member "query" case))) in
    let result = member "outcome" case in
    match string (member "status" result) with
    | "solved" ->
      incr solved;
      let ids = List.map string (list (member "edges" result)) in
      let labels = List.map string (list (member "labels" result)) in
      let nodes = List.map string (list (member "nodes" result)) in
      let edges = List.map (fun id ->
        match List.find_opt (fun (e:edge) -> e.id=id) q.graph.edges with
        | Some e -> e | None -> fail "unknown edge") ids in
      let vertex = ref q.start and visited = ref [q.start] in
      List.iter (fun (e:edge) ->
        if e.from_ <> !vertex then fail "adjacency";
        vertex := e.to_; visited := e.to_ :: !visited) edges;
      if List.rev !visited <> nodes || not (List.mem !vertex q.targets) ||
         List.map (fun (e:edge) -> e.label) edges <> labels then fail "graph replay";
      if not (ok (accepts q.regex labels)) then fail "AST membership";
      let machine = automaton (ok (compile q.regex)) in
      let evidence = member "automaton" result in
      let transitions = List.map integer (list (member "transition_ids" evidence)) in
      let expected_states = List.map integer (list (member "states" evidence)) in
      let state = ref machine.initial and states = ref [machine.initial] in
      let remaining = ref labels in
      List.iter (fun id ->
        let t = match List.find_opt (fun t -> t.transition_id=id) machine.transitions with
          | Some t -> t | None -> fail "transition identifier" in
        if t.source <> !state then fail "NFA adjacency";
        (match t.token, !remaining with
         | None, _ -> ()
         | Some token, head::tail when token=head -> remaining := tail
         | _ -> fail "NFA label");
        state := t.destination; states := !state :: !states) transitions;
      if !state <> machine.accepting || !remaining <> [] ||
         List.rev !states <> expected_states then fail "NFA acceptance"
    | "unsat" -> (match ok (solve q) with Unsat _ -> () | _ -> fail "absence")
    | "unknown_budget" -> (match ok (solve q) with Unknown_budget _ -> () | _ -> fail "budget")
    | _ -> fail "status") cases;
  if !solved <> 2 then fail "demo witness count";
  Printf.printf "installed consumer: replayed %d demo witnesses\n" !solved
