(*
  ======================================================================
  Copyright Christophe Raffalli & Rodolphe Lepigre
  LAMA, UMR 5127 - Université Savoie Mont Blanc

  christophe.raffalli@univ-savoie.fr
  rodolphe.lepigre@univ-savoie.fr

  This software contains implements a parser combinator library together
  with a syntax extension mechanism for the OCaml language.  It  can  be
  used to write parsers using a BNF-like format through a syntax extens-
  ion called pa_parser.

  This software is governed by the CeCILL-B license under French law and
  abiding by the rules of distribution of free software.  You  can  use,
  modify and/or redistribute it under the terms of the CeCILL-B  license
  as circulated by CEA, CNRS and INRIA at the following URL:

            http://www.cecill.info

  The exercising of this freedom is conditional upon a strong obligation
  of giving credits for everybody that distributes a software incorpora-
  ting a software ruled by the current license so as  all  contributions
  to be properly identified and acknowledged.

  As a counterpart to the access to the source code and rights to  copy,
  modify and redistribute granted by the  license,  users  are  provided
  only with a limited warranty and the software's author, the holder  of
  the economic rights, and the successive licensors  have  only  limited
  liability.

  In this respect, the user's attention is drawn to the risks associated
  with loading, using, modifying and/or developing  or  reproducing  the
  software by the user in light of its specific status of free software,
  that may mean that it is complicated  to  manipulate,  and  that  also
  therefore means that it is reserved  for  developers  and  experienced
  professionals having in-depth computer knowledge. Users are  therefore
  encouraged to load and test  the  software's  suitability  as  regards
  their requirements in conditions enabling the security of  their  sys-
  tems and/or data to be ensured and, more generally, to use and operate
  it in the same conditions as regards security.

  The fact that you are presently reading this means that you  have  had
  knowledge of the CeCILL-B license and that you accept its terms.
  ======================================================================
*)
(** A small module for efficient regular expressions. *)

open Input

(** Type of a regular expression. *)
type regexp =
  | Chr of char                (** Single character.              *)
  | Set of Charset.t           (** Any character in a charset.    *)
  | Seq of regexp list         (** Sequence of regexps.           *)
  | Alt of regexp list         (** Alternative between regexps.   *)
  | Opt of regexp              (** Optional regexp.               *)
  | Str of regexp              (** Zero or more times the regexp. *)
  | Pls of regexp              (** One  or more times the regexp. *)
  | Sav of regexp * string ref (** Save what is read.             *)

(** [print_regexp ch re] prints the regexp [re] on the channel [ch]. *)
let print_regexp ch re =
  let rec pregexp ch = function
    | Chr(c)   -> Printf.fprintf ch "Chr(%C)" c
    | Set(s)   -> Printf.fprintf ch "Set(%a)" Charset.print_charset s
    | Seq(l)   -> Printf.fprintf ch "Seq([%a])" pregexps l
    | Alt(l)   -> Printf.fprintf ch "Alt([%a])" pregexps l
    | Opt(r)   -> Printf.fprintf ch "Opt(%a)" pregexp r
    | Str(r)   -> Printf.fprintf ch "Str(%a)" pregexp r
    | Pls(r)   -> Printf.fprintf ch "Pls(%a)" pregexp r
    | Sav(r,_) -> Printf.fprintf ch "Sav(%a,<ref>)" pregexp r
  and pregexps ch = function
    | []    -> ()
    | [r]   -> pregexp ch r
    | r::rs -> Printf.fprintf ch "%a;%a" pregexp r pregexps rs
  in
  pregexp ch re

type construction =
    Acc of regexp list
  | Par of regexp list * regexp list

let push x = function
  | Acc l -> Acc (x::l)
  | Par (l1, l2) -> Acc(Alt(x :: l1)::l2)

let push_alt x = function
  | Acc(Seq l1 :: l2) -> Par(l1,l2)
  | Acc(x :: l2) -> Par([x], l2)
  | Acc([]) -> assert false
  | Par(_) -> assert false

let pop = function
  | Acc l -> l
  | Par _ -> invalid_arg "Regexp: final bar."

let regexp_from_string : string -> regexp * string ref array = fun s ->
  let cs =
    let cs = ref [] in
    for i = String.length s - 1 downto 0 do
      cs := s.[i] :: !cs
    done; !cs
  in

  let read_range cs =
    let rec read_range acc = function
      | []              -> invalid_arg "Regexp: open charset."
      | ']'::cs         -> (acc, cs)
      | c1::'-'::c2::cs -> let r = Charset.range c1 c2 in
                           read_range (Charset.union acc r) cs
      | c::cs           -> read_range (Charset.add acc c) cs
    in read_range Charset.empty cs
  in
  let rec tokens cs =
    let is_spe c = List.mem c ['\\';'.';'*';'+';'?';'[';']'] in
    match cs with
    | '.' ::cs            -> `Set(Charset.full) :: tokens cs
    | '*' ::cs            -> `Str :: tokens cs
    | '+' ::cs            -> `Pls :: tokens cs
    | '?' ::cs            -> `Opt :: tokens cs
    | '\\'::'('::cs       -> `Opn :: tokens cs
    | '\\'::')'::cs       -> `Cls :: tokens cs
    | '\\'::'|'::cs       -> `Alt :: tokens cs
    | '\\'::c  ::cs       -> if is_spe c then `Chr(c) :: tokens cs
                             else invalid_arg "Regexp: invalid escape."
    | '\\'::[]            -> invalid_arg "Regexp: nothing to escape."
    | '[' ::'^':: ']'::cs -> let (rng, cs) = read_range cs in
                             let rng = Charset.add rng ']' in
                             `Set(Charset.complement rng) :: tokens cs
    | '[' ::']':: cs      -> let (rng, cs) = read_range cs in
                             `Set(Charset.add rng ']') :: tokens cs
    | '[' ::'^'::cs       -> let (rng, cs) = read_range cs in
                             `Set(Charset.complement rng) :: tokens cs
    | '[' ::cs            -> let (rng, cs) = read_range cs in
                             `Set(rng) :: tokens cs
    | c   ::cs            -> `Chr(c) :: tokens cs
    | []                  -> []
  in
  let ts = tokens cs in

  let refs = ref [] in
  let rec build_re stk acc ts =
    match (stk, acc, ts) with
    | (stk   , acc    , `Chr(c)::ts) -> build_re stk (push (Chr c) acc) ts
    | (stk   , acc    , `Set(s)::ts) -> build_re stk (push (Set s) acc) ts
    | (stk   , Acc(Alt (re::l)::acc), `Str   ::ts) -> build_re stk (Acc(Alt(Str re::l) :: acc)) ts
    | (stk   , Acc(Alt (re::l)::acc), `Pls   ::ts) -> build_re stk (Acc(Alt(Pls re::l) :: acc)) ts
    | (stk   , Acc(Alt (re::l)::acc), `Opt   ::ts) -> build_re stk (Acc(Alt(Opt re::l) :: acc)) ts
    | (stk   , Acc(re::acc), `Str   ::ts) -> build_re stk (Acc(Str re :: acc)) ts
    | (stk   , Acc(re::acc), `Pls   ::ts) -> build_re stk (Acc(Pls re :: acc)) ts
    | (stk   , Acc(re::acc), `Opt   ::ts) -> build_re stk (Acc(Opt re :: acc)) ts
    | (stk   , _     , `Str   ::_ )
    | (stk   , _     , `Pls   ::_ )
    | (stk   , _     , `Opt   ::_ ) ->
        invalid_arg "Regexp: modifier error."
    | (stk   , acc    , `Opn   ::ts) -> build_re (pop acc::stk) (Acc []) ts
    | ([]    , _      , `Cls   ::_ ) ->
        invalid_arg "Regexp: group not opened."
    | (s::stk, acc    , `Cls   ::ts) ->
        let re =
          match List.rev (pop acc) with
          | [re] -> re
          | l    -> Seq(l)
        in
        let r = ref "" in refs := r :: !refs;
        build_re stk (Acc(Sav(re,r)::s)) ts
    | (stk   , Acc(re::acc), `Alt   ::ts) -> build_re stk (Par([re],acc)) ts
    | (stk   , Acc []      , `Alt   ::ts) -> invalid_arg "Regexp: initial bar."
    | (stk   , Par _       , `Alt   ::ts) -> invalid_arg "Regexp: consecutive bar."
    | ([]    , acc    , []         ) ->
        begin
          match List.rev (pop acc) with
          | [re] -> re
          | l    -> Seq(l)
        end
    | (_     , _      , []         ) -> invalid_arg "Regexp: group error."
  in
  let re = build_re [] (Acc []) ts in
  (re, Array.of_list (List.rev !refs))

(** Exception raised when a regexp cannot be parsed. *)
exception Regexp_error of buffer * int

(** [regexp_error buf pos] raises the exception [Regexp_error(buf,pos)].
    It is only used internally, it is not given in the interface. *)
let regexp_error : type a. buffer -> int -> a = fun buf pos ->
  raise (Regexp_error(buf, pos))

(** [string_of_char_list cs] converts a list of characters into a
    [string] using a [Buffer.t]. *)
let string_of_char_list : char list -> string = fun cs ->
  let b = Buffer.create 10 in
  List.iter (Buffer.add_char b) cs;
  Buffer.contents b

(* [read_regexp re buf pos] input characters according to the regexp [re]
   in the buffer [buf] at the position [pos]. The value returned is the
   buffer and position after the input has been read successfully. In
   case of problem, the exception [Regexp_error] is raised. *)
let read_regexp : regexp -> buffer -> int -> buffer * int =
  fun re buf pos ->
    let rec sread_regexp re buf pos cs =
      (*
      Printf.eprintf "%d:%d -> %a -> %C\n%!"
        (line_num buf) pos print_regexp re (get buf pos);
      *)
      match re with
      | Chr(ch)    ->
          let (c, buf, pos) = read buf pos in
          if c = ch then (c::cs, buf, pos)
          else regexp_error buf pos
      | Set(chs)   ->
          let (c, buf, pos) = read buf pos in
          if Charset.mem chs c then (c::cs, buf, pos)
          else regexp_error buf pos
      | Seq(r::rs) ->
          let (cs, buf, pos) = sread_regexp r buf pos cs in
          sread_regexp (Seq(rs)) buf pos cs
      | Seq([])    -> (cs, buf, pos)
      | Alt(r::rs) ->
          begin
            try sread_regexp r buf pos cs
            with Regexp_error(_,_) -> sread_regexp (Alt(rs)) buf pos cs
          end
      | Alt([])    -> regexp_error buf pos
      | Opt(r)     ->
          begin
            try sread_regexp r buf pos cs
            with Regexp_error(_,_) -> (cs, buf, pos)
          end
      | Str(r)     ->
          begin
            try
              let (cs, buf, pos) = sread_regexp r buf pos cs in
              sread_regexp re buf pos cs
            with Regexp_error(_,_) -> (cs, buf, pos)
          end
      | Pls(r)     ->
          let (cs, buf, pos) = sread_regexp r buf pos cs in
          sread_regexp (Str(r)) buf pos cs
      | Sav(r,ptr) ->
          let cs0 = cs in
          let rec fn acc = function
            | cs when cs == cs0 -> string_of_char_list acc
            | c::cs -> fn (c::acc) cs
            | [] -> assert false
          in
          let (cs, _, _ as res) = sread_regexp r buf pos cs in
          ptr := fn [] cs; res
    in
    let rec read_regexp re buf pos =
      (*
      Printf.eprintf "%d:%d -> %a -> %C\n%!"
        (line_num buf) pos print_regexp re (get buf pos);
      *)
      match re with
      | Chr(ch)    ->
          let (c, buf, pos) = read buf pos in
          if c = ch then (buf, pos)
          else regexp_error buf pos
      | Set(chs)   ->
          let (c, buf, pos) = read buf pos in
          if Charset.mem chs c then (buf, pos)
          else regexp_error buf pos
      | Seq(r::rs) ->
          let (buf, pos) = read_regexp r buf pos in
          read_regexp (Seq(rs)) buf pos
      | Seq([])    -> (buf, pos)
      | Alt(r::rs) ->
          begin
            try read_regexp r buf pos
            with Regexp_error(_,_) -> read_regexp (Alt(rs)) buf pos
          end
      | Alt([])    -> regexp_error buf pos
      | Opt(r)     ->
          begin
            try read_regexp r buf pos
            with Regexp_error(_,_) -> (buf, pos)
          end
      | Str(r)     ->
          begin
            try
              let (buf, pos) = read_regexp r buf pos in
              read_regexp re buf pos
            with Regexp_error(_,_) -> (buf, pos)
          end
      | Pls(r)     ->
          let (buf, pos) = read_regexp r buf pos in
          read_regexp (Str(r)) buf pos
      | Sav(r,ptr) ->
         let (cs, buf, pos) = sread_regexp r buf pos [] in
         ptr := string_of_char_list (List.rev cs);
         (buf, pos)
    in
    read_regexp re buf pos