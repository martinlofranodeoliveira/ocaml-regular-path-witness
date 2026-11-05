(** Development 0.1.0. All limits and ordering rules are specified in docs/contract.md. *)
type regex = Empty | Epsilon | Literal of string | Union of regex * regex
           | Concat of regex * regex | Star of regex
type edge = { id : string; from_ : string; to_ : string; label : string }
type graph = { nodes : string list; edges : edge list }
type budget = { product_states : int; relaxations : int }
type query = { graph : graph; start : string; targets : string list;
               regex : regex; budget : budget }
val version : string
val default_budget : budget

type error = Invalid_input of string | Construction_limit of string
           | Verification_limit of string | Internal_error of string
val error_message : error -> string

type transition = { transition_id : int; source : int; destination : int;
                    token : string option }
type automaton = { state_count : int; initial : int; accepting : int;
                   transitions : transition list }
type compiled
val compile : regex -> (compiled, error) result
val automaton : compiled -> automaton

type counters = private { admitted : int; relaxed : int; popped : int;
                          membership_work : int }
type limit = Product_states | Relaxations | Witness_edges | Witness_bytes
           | Evidence_steps | Membership_work | Report_bytes
val limit_name : limit -> string

type witness = private {
  edges : string list; labels : string list; nodes : string list;
  transition_ids : int list; nfa_states : int list;
}
type outcome = private Solved of witness * counters | Unsat of counters
                     | Unknown_budget of limit * counters

(** Validates bounded direct inputs before allocating a product search. *)
val solve : query -> (outcome, error) result
(** Independent finite-word AST interpretation; no NFA is used. *)
val accepts : regex -> string list -> (bool, error) result
(** Revalidates the query, graph replay, automaton replay, and AST membership. *)
val check_witness : query -> witness -> (unit, error) result

(** ASCII/depth preflight followed by Yojson and a closed, duplicate-free schema. *)
val decode : string -> (query, error) result
val outcome_to_yojson : outcome -> Yojson.Safe.t
(** solve has already enforced the encoded report bound. *)
val report : outcome -> string
