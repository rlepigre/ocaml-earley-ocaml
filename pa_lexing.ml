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

(****************************************************************************
 * OCaml comments.                                                          *
 ****************************************************************************)

(*
 * The exception [Unclosed_comment(is_string, buf, pos)] is raised when
 * the comment (resp. string litteral in a comment) at position [pos] in
 * [buf] is not closed.
 *)
exception Unclosed_comment of bool * Input.buffer * int

let unclosed_comment : type a. (Input.buffer * int) -> a =
  fun (buf, pos) -> raise (Unclosed_comment (false, buf, pos))

let unclosed_comment_string : type a. (Input.buffer * int) -> a =
  fun (buf, pos) -> raise (Unclosed_comment (true, buf, pos))

(*
 * Characters to be ignored by OCaml's blank function:
 *   - ' ', '\t', '\r', '\n',
 *   - everything between "(*" and "*)" (ocaml-like comments).
 * Remarks on what is allowed inside an ocaml-like comment:
 *   - nested comments,
 *   - arbitrary string litterals (including those containing "(*" or
 *     "*)" (note that string litterals need to be closed.
 *)
let ocaml_blank buf pos =
  let rec fn state stack prev curr =
    let (buf, pos) = curr in
    let (c, buf', pos') = Input.read buf pos in
    let next = (buf', pos') in
    match (state, stack, c) with
    (* Basic blancs. *)
    | (`Ini      , []  , ' '     )
    | (`Ini      , []  , '\t'    )
    | (`Ini      , []  , '\r'    )
    | (`Ini      , []  , '\n'    ) -> fn `Ini stack curr next
    (* Comment opening. *)
    | (`Ini      , _   , '('     ) -> fn (`Opn(curr)) stack curr next
    | (`Ini      , []  , _       ) -> curr
    | (`Opn(p)   , _   , '*'     ) -> fn `Ini (p::stack) curr next
    | (`Opn(_)   , _::_, '"'     ) -> fn (`Str(curr)) stack curr next (*#*)
    | (`Opn(_)   , _::_, '{'     ) -> fn (`SOp([],curr)) stack curr next (*#*)
    | (`Opn(_)   , []  , _       ) -> prev
    | (`Opn(_)   , _   , _       ) -> fn `Ini stack curr next
    (* String litteral in a comment (including the # rules). *)
    | (`Ini      , _::_, '"'     ) -> fn (`Str(curr)) stack curr next
    | (`Str(_)   , _::_, '"'     ) -> fn `Ini stack curr next
    | (`Str(p)   , _::_, '\\'    ) -> fn (`Esc(p)) stack curr next
    | (`Esc(p)   , _::_, _       ) -> fn (`Str(p)) stack curr next
    | (`Str(p)   , _::_, '\255'  ) -> unclosed_comment_string p
    | (`Str(_)   , _::_, _       ) -> fn state stack curr next
    | (`Str(_)   , []  , _       ) -> assert false (* Impossible. *)
    | (`Esc(_)   , []  , _       ) -> assert false (* Impossible. *)
    (* Delimited string litteral in a comment. *)
    | (`Ini      , _::_, '{'     ) -> fn (`SOp([],curr)) stack curr next
    | (`SOp(l,p) , _::_, 'a'..'z')
    | (`SOp(l,p) , _::_, '_'     ) -> fn (`SOp(c::l,p)) stack curr next
    | (`SOp(_,_) , p::_, '\255'  ) -> unclosed_comment p
    | (`SOp(l,p) , _::_, '|'     ) -> fn (`SIn(List.rev l,p)) stack curr next
    | (`SOp(_,_) , _::_, _       ) -> fn `Ini stack curr next
    | (`SIn(l,p) , _::_, '|'     ) -> fn (`SCl(l,(l,p))) stack curr next
    | (`SIn(_,p) , _::_, '\255'  ) -> unclosed_comment_string p
    | (`SIn(_,_) , _::_, _       ) -> fn state stack curr next
    | (`SCl([],b), _::_, '}'     ) -> fn `Ini stack curr next
    | (`SCl([],b), _::_, '\255'  ) -> unclosed_comment_string (snd b)
    | (`SCl([],b), _::_, _       ) -> fn (`SIn(b)) stack curr next
    | (`SCl(l,b) , _::_, c       ) -> if c = List.hd l then
                                        let l = List.tl l in
                                        fn (`SCl(l, b)) stack curr next
                                      else
                                        fn (`SIn(b)) stack curr next
    | (`SOp(_,_) , []  , _       ) -> assert false (* Impossible. *)
    | (`SIn(_,_) , []  , _       ) -> assert false (* Impossible. *)
    | (`SCl(_,_) , []  , _       ) -> assert false (* Impossible. *)
    (* Comment closing. *)
    | (`Ini      , _::_, '*'     ) -> fn `Cls stack curr next
    | (`Cls      , _::_, '*'     ) -> fn `Cls stack curr next
    | (`Cls      , _::s, ')'     ) -> fn `Ini s curr next
    | (`Cls      , _::_, _       ) -> fn `Ini stack curr next
    | (`Cls      , []  , _       ) -> assert false (* Impossible. *)
    (* Comment contents (excluding string litterals). *)
    | (`Ini     , p::_, '\255'  ) -> unclosed_comment p
    | (`Ini     , _::_, _       ) -> fn `Ini stack curr next
  in
  fn `Ini [] (buf, pos) (buf, pos)

(****************************************************************************
 * Keywords management.                                                     *
 ****************************************************************************)

let test_end_kw =
  let f buf pos =
    let (c,_,_) = Input.read buf pos in
    match c with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '\'' -> ((), false)
    | _                                           -> ((), true )
  in
  Decap.test ~name:"test_end_kw" Charset.full_charset f

let key_word s =
  if String.length s <= 0 then
    invalid_arg "Pa_lexing.key_word (empty keyword)";
  parser STR(s) - test_end_kw -> ()

let mutable_kw     = key_word "mutable"
let private_kw     = key_word "private"
let virtual_kw     = key_word "virtual"
let rec_kw         = key_word "rec"
let to_kw          = key_word "to"
let downto_kw      = key_word "downto"
let joker_kw       = key_word "_"
let method_kw      = key_word "method"
let object_kw      = key_word "object"
let class_kw       = key_word "class"
let inherit_kw     = key_word "inherit"
let as_kw          = key_word "as"
let of_kw          = key_word "of"
let module_kw      = key_word "module"
let open_kw        = key_word "open"
let include_kw     = key_word "include"
let type_kw        = key_word "type"
let val_kw         = key_word "val"
let external_kw    = key_word "external"
let constraint_kw  = key_word "constraint"
let begin_kw       = key_word "begin"
let end_kw         = key_word "end"
let and_kw         = key_word "and"
let true_kw        = key_word "true"
let false_kw       = key_word "false"
let exception_kw   = key_word "exception"
let when_kw        = key_word "when"
let fun_kw         = key_word "fun"
let function_kw    = key_word "function"
let let_kw         = key_word "let"
let in_kw          = key_word "in"
let initializer_kw = key_word "initializer"
let with_kw        = key_word "with"
let while_kw       = key_word "while"
let for_kw         = key_word "for"
let do_kw          = key_word "do"
let done_kw        = key_word "done"
let new_kw         = key_word "new"
let assert_kw      = key_word "assert"
let if_kw          = key_word "if"
let then_kw        = key_word "then"
let else_kw        = key_word "else"
let try_kw         = key_word "try"
let match_kw       = key_word "match"
let struct_kw      = key_word "struct"
let functor_kw     = key_word "functor"
let sig_kw         = key_word "sig"
let lazy_kw        = key_word "lazy"
let parser_kw      = key_word "parser"
let cached_kw      = key_word "cached"

(****************************************************************************
 * Identifiers.                                                             *
 ****************************************************************************)

let make_reserved l =
  let cmp s1 s2 = String.compare s2 s1 in
  let re_from_list l =
    let l = List.map (fun s -> "\\(" ^ Str.quote s ^ "\\)") l in
    Str.regexp (String.concat "\\|" l)
  in
  let reserved = ref (List.sort cmp l) in
  let re = ref (re_from_list !reserved) in
  let is_reserved s =
    Str.string_match !re s 0 && Str.match_end () = String.length s
  in
  let add_reserved s =
    reserved := List.sort cmp (s::!reserved);
    re := re_from_list !reserved
  in
  (is_reserved, add_reserved)

let reserved_ids =
  [ "and" ; "as" ; "assert" ; "asr" ; "begin" ; "class" ; "constraint" ; "do"
  ; "done" ; "downto" ; "else" ; "end" ; "exception" ; "external" ; "false"
  ; "for" ; "function" ; "functor" ; "fun" ; "if" ; "in" ; "include"
  ; "inherit" ; "initializer" ; "land" ; "lazy" ; "let" ; "lor" ; "lsl"
  ; "lsr" ; "lxor" ; "match" ; "method" ; "mod" ; "module" ; "mutable"
  ; "new" ; "object" ; "of" ; "open" ; "or" ; "private" ; "rec" ; "sig"
  ; "struct" ; "then" ; "to" ; "true" ; "try" ; "type" ; "val" ; "virtual"
  ; "when" ; "while" ; "with" ]

let reserved_symbs =
  [ "#" ; "'" ; "(" ; ")" ; "," ; "->" ; "." ; ".." ; ":" ; ":>" ; ";" ; ";;"
  ; "<-" ; ">]" ; ">}" ; "?" ; "[" ; "[<" ; "[>" ; "[|" ; "]" ; "_" ; "`"
  ; "{" ; "{<" ; "|" ; "|]" ; "}" ; "~" ]

let (is_reserved_id  , add_reserved_id  ) = make_reserved reserved_ids
let (is_reserved_symb, add_reserved_symb) = make_reserved reserved_symbs

let not_special =
  let special = "!$%&*+./:<=>?@^|~-" in
  let cs = ref Charset.empty_charset in
  String.iter (fun c -> cs := Charset.add !cs c) special;
  Decap.not_in_charset ~name:"not_special" !cs

let parser  ident = id:''[A-Za-z_][a-zA-Z0-9_']*'' ->
  if is_reserved_id id then Decap.give_up (id ^ " is a keyword..."); id

(* NOTE "_" is not a valid "lident", it is handled separately. *)
let parser lident = id:''\([a-z][a-zA-Z0-9_']*\)\|\([_][a-zA-Z0-9_']+\)'' ->
  if is_reserved_id id then Decap.give_up (id ^ " is a keyword..."); id

let parser uident = ''[A-Z][a-zA-Z0-9_']*''

(****************************************************************************
 * Constants and litterals.                                                 *
 ****************************************************************************)

let union_re l = String.concat "\\|" (List.map (Printf.sprintf "\\(%s\\)") l)

let cs_to_string cs =
  String.concat "" (List.map (fun c -> String.make 1 c) cs)

let single_char c =
  let s = String.make 1 c in
  let f str pos =
    let (c', str', pos') = Input.read str pos in
    if c' = c then
      let (c'', _, _) = Input.read str' pos' in
      if c'' = c then Decap.give_up "" (* FIXME *)
      else ((), str', pos')
    else
      Decap.give_up "" (* FIXME *)
  in
  Decap.black_box f (Charset.singleton c) false s

let double_char c =
  let s = String.make 2 c in
  let f str pos =
   let (c', str', pos') = Input.read str pos in
   if c' = c then
     let (c'', str', pos') = Input.read str' pos' in
     if c'' <> c then Decap.give_up "" (* FIXME *)
     else ((), str', pos')
   else
     Decap.give_up "" (* FIXME *)
  in
  Decap.black_box f (Charset.singleton c) false s

(* Special characters and delimiters. *)

let semi_col        = single_char ';'
let double_semi_col = double_char ';'
let single_quote    = single_char '\''
let double_quote    = double_char '\''

(* Boolean litteral. *)

let parser bool_lit : string Decap.grammar =
  | false_kw -> "false"
  | true_kw  -> "true"

(* Int litteral. *)

let int_litteral : (string * char option) Decap.grammar =
  let int_re = union_re
    [ "[0][xX][0-9a-fA-F][0-9a-fA-F_]*" (* Hexadecimal *)
    ; "[0][oO][0-7][0-7_]*"             (* Octal *)
    ; "[0][bB][01][01_]*"               (* Binary *)
    ; "[0-9][0-9_]*" ]                  (* Decimal (NOTE needs to be last. *)
  in
  let suffix_cs = Charset.(union (range 'g' 'z') (range 'G' 'Z')) in
  parser i:RE(int_re) - s:(Decap.in_charset suffix_cs)? _:Decap.relax

(* Float litteral. *)
let float_litteral : (string * char option) Decap.grammar =
  let float_re = union_re
    [ "[0-9][0-9_]*[eE][+-]?[0-9][0-9_]*"
    ; "[0-9][0-9_]*[.][0-9_]*\\([eE][+-][0-9][0-9_]*\\)?" ]
  in
  let suffix_cs = Charset.(union (range 'g' 'z') (range 'G' 'Z')) in
  parser f:RE(float_re) - s:(Decap.in_charset suffix_cs)? _:Decap.relax

(* Char litteral. *)

let escaped_char : char Decap.grammar =
  let char_dec = "[0-9][0-9][0-9]" in
  let char_hex = "[x][0-9a-fA-F][0-9a-fA-F]" in
  let char_esc = "[\\\\\\\"\\\'ntbrs ]" in
  parser
    | e:RE(char_dec) -> char_of_int (int_of_string e)
    | e:RE(char_hex) -> char_of_int (int_of_string ("0" ^ e))
    | e:RE(char_esc) ->
        begin
          match e.[0] with
          | 'n' -> '\n'
          | 't' -> '\t'
          | 'b' -> '\b'
          | 'r' -> '\r'
          | 's' -> ' '
          | c   -> c
        end

let char_litteral : char Decap.grammar =
  let char_reg = "[^\\\\\\\']" in
  let single_char =
    parser
      | c:RE(char_reg)        -> c.[0]
      | '\\' - e:escaped_char -> e
  in
  parser _:single_quote - c:single_char - '\''

(* String litteral. *)

let quoted_string : (string * string option) Decap.grammar =
  let f buf pos =
    let rec fn st str buf pos =
      let (c, buf', pos') = Input.read buf pos in
      match (st, c) with
      | (`Ini          , '{'     ) -> fn (`Opn([])) str buf' pos'
      | (`Opn(l)       , 'a'..'z')
      | (`Opn(l)       , '_'     ) -> fn (`Opn(c::l)) str buf' pos'
      | (`Opn(l)       , '|'     ) -> fn (`Cnt(List.rev l)) str buf' pos'
      | (`Cnt(l)       , '|'     ) -> fn (`Cls(l,[],l)) str buf' pos'
      | (`Cnt(l)       , '\255'  ) -> Decap.give_up ""
      | (`Cnt(_)       , _       ) -> fn st (c::str) buf' pos'
      | (`Cls([]  ,_,l), '}'     ) -> (str, l, buf', pos') (* Success. *)
      | (`Cls([]  ,_,_), '\255'  ) -> Decap.give_up ""
      | (`Cls([]  ,b,l), _       ) -> fn (`Cnt(l)) (List.append b str) buf' pos'
      | (`Cls(_::_,_,_), '\255'  ) -> Decap.give_up ""
      | (`Cls(x::y,b,l), _       ) ->
          if x = c then fn (`Cls(y,x::b,l)) str buf' pos'
          else fn (`Cnt(l)) (List.append b str) buf' pos'
      | (_           , _       ) -> Decap.give_up ""
    in
    let (cs, id, buf, pos) = fn `Ini [] buf pos in
    let r = (cs_to_string cs, Some (cs_to_string id)) in
    (r, buf, pos)
  in
  Decap.black_box f (Charset.singleton '{') false "quoted_string"

let normal_string : string Decap.grammar =
  let char_reg = "[^\\\\\\\"]" in
  let single_char = parser
    | c:RE(char_reg)                                       -> c.[0]
    | '\\' - e:{'\n' -> Decap.give_up "" | e:escaped_char} -> e
  in
  let internal = parser
    cs:single_char* css:{_:"\\\n" _:RE("[ \t]*") single_char*}* ->
      cs_to_string (List.flatten (cs :: css))
  in
  parser '"' - (Decap.change_layout internal Decap.no_blank) - '"'

let string_litteral : (string * string option) Decap.grammar =
  parser
    | s:normal_string -> (s, None)
    | quoted_string

(* Regexp litteral. *)

let regexp_litteral : string Decap.grammar =
  let char_reg = "[^\\\\']" in
  let char_esc = "[ntbrs\\\\']" in
  let single_char = parser
    | c:RE(char_reg)      -> c.[0]
    | '\\' e:RE(char_esc) ->
        begin
          match e.[0] with
          | 'n' -> '\n'
          | 't' -> '\t'
          | 'b' -> '\b'
          | 'r' -> '\r'
          | 's' -> ' '
          | c   -> c
        end
  in
  let internal = parser cs:single_char* -> cs_to_string cs in
  parser _:double_quote - (Decap.change_layout internal Decap.no_blank) - "''"
