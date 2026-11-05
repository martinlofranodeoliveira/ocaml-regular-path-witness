type regex = Empty | Epsilon | Literal of string | Union of regex * regex
           | Concat of regex * regex | Star of regex
type edge = { id : string; from_ : string; to_ : string; label : string }
type graph = { nodes : string list; edges : edge list }
type budget = { product_states : int; relaxations : int }
type query = { graph : graph; start : string; targets : string list;
               regex : regex; budget : budget }
let version = "0.1.0"
let default_budget = { product_states = 4096; relaxations = 100000 }
type error = Invalid_input of string | Construction_limit of string
           | Verification_limit of string | Internal_error of string
let error_message = function
  | Invalid_input s -> "invalid input: " ^ s
  | Construction_limit s -> "construction limit: " ^ s
  | Verification_limit s -> "verification limit: " ^ s
  | Internal_error s -> "internal verification failure: " ^ s
exception Reject of error
let invalid s = raise (Reject (Invalid_input s))
let guarded f = try Ok (f ()) with Reject e -> Error e

(* Never take List.length or copy an unadmitted caller list. This also stops
   cyclic OCaml lists after at most maximum+1 cells. *)
let bounded maximum xs description =
  let rec walk n acc = function
    | [] -> List.rev acc
    | _ :: _ when n = maximum -> invalid description
    | x :: tail -> walk (n + 1) (x :: acc) tail
  in walk 0 [] xs
let token maximum s =
  let n = String.length s in
  n >= 1 && n <= maximum && String.for_all (function
    | 'A'..'Z' | 'a'..'z' | '0'..'9' | '_' | '.' | '-' -> true
    | _ -> false) s
let require_token maximum s description =
  if not (token maximum s) then invalid description
let validate_ast ast =
  let count = ref 0 in
  let rec visit depth = function
    | _ when depth > 16 -> raise (Reject (Construction_limit "AST depth exceeds 16"))
    | expression ->
      incr count;
      if !count > 64 then raise (Reject (Construction_limit "AST nodes exceed 64"));
      match expression with
      | Empty | Epsilon -> ()
      | Literal s -> require_token 16 s "literal token"
      | Union (a,b) | Concat (a,b) -> visit (depth+1) a; visit (depth+1) b
      | Star a -> visit (depth+1) a
  in visit 1 ast
let unique description xs =
  let seen = Hashtbl.create 32 in
  List.iter (fun s ->
    if Hashtbl.mem seen s then invalid description;
    Hashtbl.add seen s ()) xs
let admit q =
  let nodes = bounded 32 q.graph.nodes "graph nodes exceed 32" in
  let edges = bounded 128 q.graph.edges "graph edges exceed 128" in
  let targets = bounded 32 q.targets "targets exceed 32" in
  List.iter (fun s -> require_token 32 s "node identifier") nodes;
  unique "duplicate node identifier" nodes;
  List.iter (fun (e:edge) ->
    require_token 32 e.id "edge identifier";
    require_token 32 e.from_ "edge source";
    require_token 32 e.to_ "edge destination";
    require_token 16 e.label "edge label";
    if not (List.mem e.from_ nodes && List.mem e.to_ nodes) then
      invalid "unknown edge endpoint") edges;
  unique "duplicate edge identifier" (List.map (fun (e:edge) -> e.id) edges);
  require_token 32 q.start "start identifier";
  if not (List.mem q.start nodes) then invalid "unknown start";
  List.iter (fun s ->
    require_token 32 s "target identifier";
    if not (List.mem s nodes) then invalid "unknown target") targets;
  unique "duplicate target" targets;
  if q.budget.product_states < 0 || q.budget.product_states > 4096 ||
     q.budget.relaxations < 0 || q.budget.relaxations > 100000 then
    invalid "search budget outside supported range";
  validate_ast q.regex;
  { q with graph = { nodes = List.sort String.compare nodes;
                     edges = List.sort (fun (a:edge) b -> String.compare a.id b.id) edges };
           targets = List.sort String.compare targets }

type transition = { transition_id : int; source : int; destination : int;
                    token : string option }
type automaton = { state_count : int; initial : int; accepting : int;
                   transitions : transition list }
type compiled = { machine : automaton; by_id : transition array;
                  outgoing : transition list array; expression : regex }
let automaton c = c.machine
let compile_exn expression =
  validate_ast expression;
  let states = ref 0 and transitions = ref [] and next_transition = ref 0 in
  let state () =
    if !states = 128 then raise (Reject (Construction_limit "NFA states exceed 128"));
    let n = !states in incr states; n
  in
  let emit source destination token =
    let transition_id = !next_transition in incr next_transition;
    transitions := { transition_id; source; destination; token } :: !transitions
  in
  let rec build expression =
    let entry = state () in
    let exit = state () in
    (match expression with
     | Empty -> ()
     | Epsilon -> emit entry exit None
     | Literal s -> emit entry exit (Some s)
     | Union (a,b) ->
       let ae, ax = build a in
       let be, bx = build b in
       emit entry ae None; emit entry be None;
       emit ax exit None; emit bx exit None
     | Concat (a,b) ->
       let ae, ax = build a in
       let be, bx = build b in
       emit entry ae None; emit ax be None; emit bx exit None
     | Star a ->
       let ae, ax = build a in
       emit entry exit None; emit entry ae None;
       emit ax ae None; emit ax exit None);
    entry, exit
  in
  let initial, accepting = build expression in
  let transitions = List.rev !transitions in
  let outgoing = Array.make !states [] in
  List.iter (fun t -> outgoing.(t.source) <- t :: outgoing.(t.source)) transitions;
  { machine = { state_count = !states; initial; accepting; transitions };
    by_id = Array.of_list transitions;
    outgoing = Array.map List.rev outgoing; expression }
let compile ast = guarded (fun () -> compile_exn ast)

(* A separate semantics: finite sets of word positions. In Star, every position
   enters the queue once, including when the child accepts the empty word. *)
let membership expression word =
  let word = Array.of_list word in
  let n = Array.length word and work = ref 0 in
  let tick () =
    if !work = 2000000 then raise (Reject (Verification_limit "membership_work"));
    incr work
  in
  let union_into destination source =
    for i = 0 to n do tick (); if source.(i) then destination.(i) <- true done
  in
  let rec eval expression position =
    tick ();
    let result = Array.make (n+1) false in
    (match expression with
     | Empty -> ()
     | Epsilon -> result.(position) <- true
     | Literal s ->
       if position < n && word.(position) = s then result.(position+1) <- true
     | Union (a,b) ->
       let left = eval a position in
       let right = eval b position in
       union_into result left; union_into result right
     | Concat (a,b) ->
       let left = eval a position in
       for i = 0 to n do
         tick (); if left.(i) then union_into result (eval b i)
       done
     | Star child ->
       let queue = Queue.create () in
       result.(position) <- true; Queue.add position queue;
       while not (Queue.is_empty queue) do
         tick ();
         let reached = eval child (Queue.take queue) in
         for i = 0 to n do
           tick ();
           if reached.(i) && not result.(i) then
             (result.(i) <- true; Queue.add i queue)
         done
       done);
    result
  in
  let positions = eval expression 0 in positions.(n), !work
let accepts ast word = guarded (fun () ->
  validate_ast ast;
  let word = bounded 128 word "word length exceeds 128" in
  List.iter (fun s -> require_token 16 s "word token") word;
  fst (membership ast word))

type counters = { admitted : int; relaxed : int; popped : int; membership_work : int }
type limit = Product_states | Relaxations | Witness_edges | Witness_bytes
           | Evidence_steps | Membership_work | Report_bytes
let limit_name = function
  | Product_states -> "product_states" | Relaxations -> "relaxations"
  | Witness_edges -> "witness_edges" | Witness_bytes -> "witness_bytes"
  | Evidence_steps -> "evidence_steps" | Membership_work -> "membership_work"
  | Report_bytes -> "report_bytes"
type witness = { edges : string list; labels : string list; nodes : string list;
                 transition_ids : int list; nfa_states : int list }
type outcome = Solved of witness * counters | Unsat of counters
             | Unknown_budget of limit * counters
let strings xs = `List (List.map (fun s -> `String s) xs)
let ints xs = `List (List.map (fun n -> `Int n) xs)
let outcome_to_yojson outcome =
  let stats c = `Assoc ["admitted", `Int c.admitted; "relaxed", `Int c.relaxed;
    "popped", `Int c.popped; "membership_work", `Int c.membership_work] in
  match outcome with
  | Solved (w,c) -> `Assoc ["status", `String "solved";
      "edges", strings w.edges; "labels", strings w.labels; "nodes", strings w.nodes;
      "automaton", `Assoc ["transition_ids", ints w.transition_ids;
                            "states", ints w.nfa_states]; "counters", stats c]
  | Unsat c -> `Assoc ["status", `String "unsat"; "counters", stats c]
  | Unknown_budget (reason,c) -> `Assoc ["status", `String "unknown_budget";
      "reason", `String (limit_name reason); "counters", stats c]
let report outcome = Yojson.Safe.to_string (outcome_to_yojson outcome)

let payload w =
  List.fold_left (fun n s -> n + String.length s) 0 (w.edges @ w.labels @ w.nodes)
let replay q compiled w =
  let fail () = raise (Reject (Internal_error "witness replay")) in
  let ids = bounded 128 w.edges "witness edges" in
  let labels = bounded 128 w.labels "witness labels" in
  let nodes = bounded 129 w.nodes "witness nodes" in
  let run = bounded 4096 w.transition_ids "automaton evidence" in
  let states = bounded 4097 w.nfa_states "automaton states" in
  if payload w > 8192 then fail ();
  let edges = List.map (fun id ->
    match List.find_opt (fun (e:edge) -> e.id = id) q.graph.edges with
    | Some e -> e | None -> fail ()) ids in
  let vertex = ref q.start in
  let expected_nodes = ref [q.start] in
  List.iter (fun (e:edge) ->
    if e.from_ <> !vertex then fail ();
    vertex := e.to_; expected_nodes := e.to_ :: !expected_nodes) edges;
  if List.rev !expected_nodes <> nodes ||
     List.map (fun (e:edge) -> e.label) edges <> labels ||
     not (List.mem !vertex q.targets) then fail ();
  let state = ref compiled.machine.initial in
  let expected_states = ref [!state] in
  let remaining = ref edges in
  List.iter (fun id ->
    if id < 0 || id >= Array.length compiled.by_id then fail ();
    let t = compiled.by_id.(id) in
    if t.source <> !state then fail ();
    (match t.token with
     | None -> ()
     | Some label ->
       match !remaining with
       | e :: rest when e.label = label -> remaining := rest
       | _ -> fail ());
    state := t.destination; expected_states := !state :: !expected_states) run;
  if !remaining <> [] || !state <> compiled.machine.accepting ||
     List.rev !expected_states <> states then fail ();
  let accepted, work = membership compiled.expression labels in
  if not accepted then fail ();
  work
let check_witness q w = guarded (fun () ->
  let q = admit q in
  let compiled = compile_exn q.regex in
  ignore (replay q compiled w))

type item = { vertex : int; state : int; count : int; word : string list;
              ids : string list; run_rev : int list; steps : int; bytes : int }
let compare_key a b =
  let c = Int.compare a.count b.count in if c <> 0 then c else
  let c = List.compare String.compare a.word b.word in if c <> 0 then c else
  List.compare String.compare a.ids b.ids
exception Exhausted of limit
let solve query = guarded (fun () ->
  let q = admit query in
  let compiled = compile_exn q.regex in
  let admitted = ref 0 and relaxed = ref 0 and popped = ref 0 and verified = ref 0 in
  let counters () = { admitted = !admitted; relaxed = !relaxed;
                     popped = !popped; membership_work = !verified } in
  let search () =
    if q.targets = [] then Unsat (counters ()) else
    let vertices = Array.of_list q.graph.nodes in
    let node_id s =
      let rec find i = if vertices.(i) = s then i else find (i+1) in find 0
    in
    let ns = compiled.machine.state_count in
    let size = Array.length vertices * ns in
    let adjacency = Array.make (Array.length vertices) [] in
    List.iter (fun (e:edge) ->
      let i = node_id e.from_ in adjacency.(i) <- e :: adjacency.(i)) q.graph.edges;
    Array.iteri (fun i xs -> adjacency.(i) <- List.rev xs) adjacency;
    let best : item option array = Array.make size None in
    (* Indexed decrease-key heap: at most one queued entry per product pair. *)
    let heap = Array.make size 0 and positions = Array.make size (-1) in
    let used = ref 0 in
    let get i = match best.(i) with Some x -> x | None -> assert false in
    let less a b =
      let c = compare_key (get a) (get b) in c < 0 || (c = 0 && a < b)
    in
    let swap i j =
      let a = heap.(i) and b = heap.(j) in
      heap.(i) <- b; heap.(j) <- a; positions.(a) <- j; positions.(b) <- i
    in
    let rec up i = if i > 0 then
      let p = (i-1)/2 in if less heap.(i) heap.(p) then (swap i p; up p)
    in
    let rec down i =
      let left = 2*i+1 in
      if left < !used then (
        let right = left+1 in
        let child = if right < !used && less heap.(right) heap.(left) then right else left in
        if less heap.(child) heap.(i) then (swap child i; down child))
    in
    let put index item =
      (match best.(index) with
       | None ->
         if !admitted = q.budget.product_states then raise (Exhausted Product_states);
         incr admitted
       | Some _ -> ());
      if positions.(index) = -2 then
        raise (Reject (Internal_error "settled key improved"));
      best.(index) <- Some item;
      if positions.(index) >= 0 then up positions.(index)
      else (
        heap.(!used) <- index; positions.(index) <- !used; incr used; up (!used-1))
    in
    let pop () =
      let index = heap.(0) in
      decr used;
      if !used > 0 then (
        heap.(0) <- heap.(!used); positions.(heap.(0)) <- 0; down 0);
      positions.(index) <- -2;
      incr popped; get index
    in
    let initial_vertex = node_id q.start in
    put (initial_vertex*ns + compiled.machine.initial)
      { vertex = initial_vertex; state = compiled.machine.initial; count = 0;
        word = []; ids = []; run_rev = []; steps = 0; bytes = String.length q.start };
    let relax current transition edge =
      if !relaxed = q.budget.relaxations then raise (Exhausted Relaxations);
      incr relaxed;
      let candidate = match edge with
        | None -> { current with state = transition.destination;
            run_rev = transition.transition_id :: current.run_rev; steps = current.steps+1 }
        | Some (e:edge) ->
          { vertex = node_id e.to_; state = transition.destination;
            count = current.count+1; word = current.word @ [e.label];
            ids = current.ids @ [e.id];
            run_rev = transition.transition_id :: current.run_rev; steps = current.steps+1;
            bytes = current.bytes + String.length e.id + String.length e.label + String.length e.to_ }
      in
      let index = candidate.vertex*ns + candidate.state in
      let improves = match best.(index) with None -> true
        | Some previous -> compare_key candidate previous < 0 in
      if improves then (
        if candidate.count > 128 then raise (Exhausted Witness_edges);
        if candidate.bytes > 8192 then raise (Exhausted Witness_bytes);
        if candidate.steps > 4096 then raise (Exhausted Evidence_steps);
        put index candidate)
    in
    let rec loop () =
      if !used = 0 then Unsat (counters ()) else
      let current = pop () in
      if current.state = compiled.machine.accepting &&
         List.mem vertices.(current.vertex) q.targets then (
        let edges = List.map (fun id ->
          List.find (fun (e:edge) -> e.id = id) q.graph.edges) current.ids in
        let nodes = q.start :: List.map (fun (e:edge) -> e.to_) edges in
        let transition_ids = List.rev current.run_rev in
        let states_rev = List.fold_left (fun acc id ->
          compiled.by_id.(id).destination :: acc) [compiled.machine.initial] transition_ids in
        let witness = { edges = current.ids; labels = current.word; nodes;
                        transition_ids; nfa_states = List.rev states_rev } in
        (try verified := replay q compiled witness with
         | Reject (Verification_limit _) -> verified := 2000000; raise (Exhausted Membership_work));
        Solved (witness, counters ()))
      else (
        List.iter (fun transition -> match transition.token with
          | None -> relax current transition None
          | Some label -> List.iter (fun (e:edge) ->
              if e.label = label then relax current transition (Some e)) adjacency.(current.vertex))
          compiled.outgoing.(current.state);
        loop ())
    in loop ()
  in
  let outcome = try search () with Exhausted limit -> Unknown_budget (limit, counters ()) in
  if String.length (report outcome) > 65536 then Unknown_budget (Report_bytes, counters ())
  else outcome)

(* This is a lexical resource preflight, not a JSON parser. Yojson owns parsing. *)
let preflight text =
  if String.length text > 131072 then invalid "JSON bytes exceed 131072";
  let quoted = ref false and escaped = ref false and depth = ref 0 in
  String.iter (fun ch ->
    let byte = Char.code ch in
    if byte > 127 then invalid "raw JSON must be ASCII";
    if !quoted then (
      if byte < 32 then invalid "raw control byte in string";
      if !escaped then escaped := false
      else if ch = '\\' then escaped := true
      else if ch = '"' then quoted := false)
    else match ch with
      | '"' -> quoted := true
      | '/' -> invalid "JSON comments are unsupported"
      | '{' | '[' -> incr depth; if !depth > 64 then invalid "JSON depth exceeds 64"
      | '}' | ']' -> decr depth; if !depth < 0 then invalid "unbalanced JSON"
      | _ -> if byte < 32 && ch <> '\n' && ch <> '\r' && ch <> '\t' then
               invalid "raw control byte outside string") text;
  if !quoted || !depth <> 0 then invalid "incomplete JSON"
let object_fields allowed = function
  | `Assoc fields ->
    let seen = Hashtbl.create 8 in
    List.iter (fun (key,_) ->
      if not (List.mem key allowed) then invalid "unknown object field";
      if Hashtbl.mem seen key then invalid "duplicate object field";
      Hashtbl.add seen key ()) fields;
    fields
  | _ -> invalid "expected object"
let field fields name = match List.assoc_opt name fields with
  | Some value -> value | None -> invalid "missing object field"
let string_value = function `String s -> s | _ -> invalid "expected string"
let int_value = function `Int n -> n | _ -> invalid "expected bounded integer"
let list_value maximum = function
  | `List xs -> bounded maximum xs "array exceeds limit"
  | _ -> invalid "expected array"
let decode text = guarded (fun () ->
  preflight text;
  let json = try Yojson.Safe.from_string text with
    | Yojson.Json_error _ -> invalid "malformed JSON" in
  let ast_nodes = ref 0 in
  let rec expression depth json =
    if depth > 16 then raise (Reject (Construction_limit "AST depth exceeds 16"));
    incr ast_nodes;
    if !ast_nodes > 64 then raise (Reject (Construction_limit "AST nodes exceed 64"));
    let fields = object_fields ["type"; "label"; "left"; "right"; "child"] json in
    let tag = string_value (field fields "type") in
    let exact names = ignore (object_fields names json) in
    match tag with
    | "Empty" -> exact ["type"]; Empty
    | "Epsilon" -> exact ["type"]; Epsilon
    | "Literal" -> exact ["type";"label"]; Literal (string_value (field fields "label"))
    | "Union" | "Concat" ->
      exact ["type";"left";"right"];
      let left = expression (depth+1) (field fields "left") in
      let right = expression (depth+1) (field fields "right") in
      if tag = "Union" then Union (left,right) else Concat (left,right)
    | "Star" -> exact ["type";"child"]; Star (expression (depth+1) (field fields "child"))
    | _ -> invalid "unknown AST tag"
  in
  let top = object_fields ["graph";"start";"targets";"regex";"budget"] json in
  let graph = object_fields ["nodes";"edges"] (field top "graph") in
  let nodes = List.map string_value (list_value 32 (field graph "nodes")) in
  let edges = List.map (fun json ->
    let fields = object_fields ["id";"from";"to";"label"] json in
    { id = string_value (field fields "id"); from_ = string_value (field fields "from");
      to_ = string_value (field fields "to"); label = string_value (field fields "label") })
    (list_value 128 (field graph "edges")) in
  let targets = List.map string_value (list_value 32 (field top "targets")) in
  let budget = match List.assoc_opt "budget" top with
    | None -> default_budget
    | Some json ->
      let fields = object_fields ["product_states";"relaxations"] json in
      { product_states = int_value (field fields "product_states");
        relaxations = int_value (field fields "relaxations") } in
  let regex = expression 1 (field top "regex") in
  admit { graph = { nodes; edges }; start = string_value (field top "start");
          targets; regex; budget })
