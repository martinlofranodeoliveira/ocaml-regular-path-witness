(* Independently authored tiny-case oracle. No compiled automaton, production
   membership function, or production search is called here. *)
open Regular_path_witness
module Positions = Set.Make(Int)
type answer = Found of string list | Absent | Limit
exception Stop
let decide ?(maximum_work=2000000) q =
  let work = ref 0 in
  let tick () = incr work; if !work > maximum_work then raise Stop in
  let rec size = function
    | Empty | Epsilon | Literal _ -> 1
    | Union (a,b) | Concat (a,b) -> 1 + size a + size b
    | Star a -> 1 + size a in
  let belongs word =
    let word = Array.of_list word in
    let rec interpret expression positions =
      tick ();
      match expression with
      | Empty -> Positions.empty
      | Epsilon -> positions
      | Literal s -> Positions.fold (fun p result ->
          tick ();
          if p < Array.length word && word.(p) = s then Positions.add (p+1) result
          else result) positions Positions.empty
      | Union (a,b) -> Positions.union (interpret a positions) (interpret b positions)
      | Concat (a,b) -> interpret b (interpret a positions)
      | Star child ->
        let rec close reached =
          tick ();
          let next = Positions.union reached (interpret child reached) in
          if Positions.equal next reached then reached else close next
        in close positions
    in Positions.mem (Array.length word) (interpret q.regex (Positions.singleton 0)) in
  let bound = List.length q.graph.nodes * 2 * size q.regex - 1 in
  let rank (_,word,ids) (_,other_word,other_ids) =
    let c = List.compare String.compare word other_word in
    if c <> 0 then c else List.compare String.compare ids other_ids in
  let rec layer length paths =
    let candidates = List.filter (fun (vertex,word,_) ->
      tick (); List.mem vertex q.targets && belongs word) paths in
    match List.sort rank candidates with
    | (_,_,ids) :: _ -> Found ids
    | [] when length = bound || paths = [] -> Absent
    | [] ->
      let next = List.fold_left (fun acc (vertex,word,ids) ->
        List.fold_left (fun acc (e:edge) ->
          tick ();
          if e.from_ = vertex then (e.to_, word @ [e.label], ids @ [e.id]) :: acc else acc)
          acc q.graph.edges) [] paths in
      layer (length+1) next
  in try layer 0 [q.start,[],[]] with Stop -> Limit
