open Regular_path_witness
let error text =
  print_endline (Yojson.Safe.to_string (`Assoc ["status", `String "invalid";
                                               "error", `String text])); 2
let execute query = match solve query with
  | Error e -> error (error_message e)
  | Ok outcome ->
    print_endline (report outcome);
    match outcome with Solved _ -> 0 | Unsat _ -> 4 | Unknown_budget _ -> 3
let read_input () =
  let buffer = Buffer.create 4096 and bytes = Bytes.create 4096 in
  let rec loop total =
    let n = input stdin bytes 0 (min 4096 (131073-total)) in
    if n = 0 then Ok (Buffer.contents buffer)
    else if total+n > 131072 then Error "JSON bytes exceed 131072"
    else (Buffer.add_subbytes buffer bytes 0 n; loop (total+n))
  in loop 0
let examples = [
  "whole-word", "{\"graph\":{\"nodes\":[\"s\",\"u\",\"v\",\"t\"],\"edges\":[{\"id\":\"a-first\",\"from\":\"s\",\"to\":\"u\",\"label\":\"a\"},{\"id\":\"z-second\",\"from\":\"u\",\"to\":\"t\",\"label\":\"b\"},{\"id\":\"z-first\",\"from\":\"s\",\"to\":\"v\",\"label\":\"a\"},{\"id\":\"a-second\",\"from\":\"v\",\"to\":\"t\",\"label\":\"a\"}]},\"start\":\"s\",\"targets\":[\"t\"],\"regex\":{\"type\":\"Concat\",\"left\":{\"type\":\"Literal\",\"label\":\"a\"},\"right\":{\"type\":\"Union\",\"left\":{\"type\":\"Literal\",\"label\":\"a\"},\"right\":{\"type\":\"Literal\",\"label\":\"b\"}}}}", Some ["z-first";"a-second"];
  "nullable-star", "{\"graph\":{\"nodes\":[\"s\"],\"edges\":[{\"id\":\"loop\",\"from\":\"s\",\"to\":\"s\",\"label\":\"a\"}]},\"start\":\"s\",\"targets\":[\"s\"],\"regex\":{\"type\":\"Star\",\"child\":{\"type\":\"Union\",\"left\":{\"type\":\"Epsilon\"},\"right\":{\"type\":\"Literal\",\"label\":\"a\"}}}}", Some [];
  "empty-language", "{\"graph\":{\"nodes\":[\"s\"],\"edges\":[]},\"start\":\"s\",\"targets\":[\"s\"],\"regex\":{\"type\":\"Empty\"}}", None;
  "bounded", "{\"graph\":{\"nodes\":[\"s\"],\"edges\":[]},\"start\":\"s\",\"targets\":[\"s\"],\"regex\":{\"type\":\"Epsilon\"},\"budget\":{\"product_states\":0,\"relaxations\":100000}}", None
]
let demo asserting =
  let valid = ref true in
  let cases = List.map (fun (name,text,expected) ->
    match decode text with
    | Error _ -> failwith "internal demo input"
    | Ok query -> match solve query with
      | Error _ -> failwith "internal demo search"
      | Ok outcome ->
        let pass = match expected, outcome with
          | Some ids, Solved (w,_) -> w.edges = ids && check_witness query w = Ok ()
          | None, Unsat _ -> name = "empty-language"
          | None, Unknown_budget (Product_states,_) -> name = "bounded"
          | _ -> false in
        valid := !valid && pass;
        Printf.eprintf "%s: %s\n%!" name (if pass then "expected result" else "FAILED");
        `Assoc ["name", `String name; "query", Yojson.Safe.from_string text;
                "outcome", outcome_to_yojson outcome]) examples in
  print_endline (Yojson.Safe.to_string (`Assoc ["version", `String version; "cases", `List cases]));
  if asserting && not !valid then 2 else 0
let main () =
  match Array.to_list Sys.argv with
  | [_;"query"] ->
    (match read_input () with
     | Error text -> error text
     | Ok text -> match decode text with Error e -> error (error_message e) | Ok q -> execute q)
  | [_;"demo"] -> demo false
  | [_;"demo";"--assert"] -> demo true
  | _ -> error "usage: regular-path-witness query | demo [--assert]"
let () =
  let code = try main () with
    | Sys_error _ -> error "input/output failure"
    | Failure _ -> error "internal demo failure" in
  exit code
