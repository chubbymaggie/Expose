%{
(* IR Grammer file *)
(* Author: David Brumley, Ivan Jager *)
(* $Id: grammar.mly 3849 2009-10-23 02:29:24Z edmcman $ *)

open Type
open Ast


(** Whether or not to strip the trailing _number from variable names *)
let strip_nums = ref false

let parse_error str =
  let {Lexing.pos_fname=f; pos_lnum=sl; pos_bol=sb; pos_cnum=sc} =
    Parsing.symbol_start_pos()
  and {Lexing.pos_lnum=el; pos_bol=eb; pos_cnum=ec } = Parsing.symbol_end_pos() in
  Printf.eprintf "%s:%i:%i-%i:%i: %s\n" f sl (sc-sb) el (ec-eb) str

  

let err s =
  prerr_endline s;
  failwith ("Parser: "^s)
    (*raise Parsing.Parse_error*)

let stripnum =
  let stripnum1 = Str.replace_first (Str.regexp "_[0-9]+$") "" in
  fun x ->
    if !strip_nums then
      stripnum1 x
    else
      x

module Scope =
struct
  let create decls =
    let h = Hashtbl.create 5700 in
    List.iter (fun v -> Hashtbl.add h (Var.name v) v) decls;
    (h, Stack.create() )

  let defscope = create []
  let cur_scope = ref defscope

  let add n t =
    let v = Var.newvar (stripnum n) t in
    Hashtbl.add (fst !cur_scope) n v;
    v
      
  let add_push n t =
    Stack.push n (snd !cur_scope);
    add n t

  let pop () =
    let (h,s) = !cur_scope in
    let n = Stack.pop s in
    Hashtbl.remove h n
      

  let get_lval n t =
    try
      let v = Hashtbl.find (fst !cur_scope) n in
      if t = None || t = Some(Var.typ v)
      then v
      else err ("Variable '"^n^"' used with inconsistent type")
    with Not_found ->
      match t with
      | Some t -> add n t
      | None -> err ("Type was never declared for '"^n^"'")
end

let mk_attr lab string =
  match lab with
  | "asm" -> Asm string
  | "address" -> Address(Int64.of_string string)
  | "set" when string = "liveout" -> Liveout
  | "str" -> StrAttr string
  | _ -> err ("Unknown attribute @"^lab)

let typ_of_string = function
  | "bool" -> reg_1
  | "u8" -> reg_8
  | "u16" -> reg_16
  | "u32" -> reg_32
  | "u64" -> reg_64
  | s -> err ("Unexpected type '"^s^"'")

let casttype_of_string = function
  | "pad"     -> CAST_UNSIGNED
  | "extend"  -> CAST_SIGNED  
  | "high"    -> CAST_HIGH    
  | "low"     -> CAST_LOW     
  | s -> err("Unexpected cast type '"^s^"'")

%}

%token <string> ID
%token <Int64.t> INT
%token <string> STRING
%token <string> COMMENT

%token LPAREN RPAREN LSQUARE RSQUARE
%token COMMA SEMI EOF COLON
%token CJMP JMP LABEL ADDR ASSERT HALT SPECIAL
%token LET IN UNKNOWN WITH TRUE FALSE EBIG ELITTLE
%token PLUS MINUS  DIVIDE MOD SMOD TIMES 
%token SDIVIDE LSHIFT RSHIFT ARSHIFT XOR NEQ
%token SLT SLE AND OR 
%token EQUAL EQUALEQUAL LT  LE NOT ASSIGN 
%token GT GE SGT SGE
%token AT QUESTION
%token LCURLY RCURLY

%start program expr

%type <Ast.program> program
%type <Ast.exp > expr
%nonassoc LET IN
%left WITH
/* If the precedence for any of these changes, pp.ml needs to be updated
   accordingly, so that it can parethesize things properly */
%left OR
%left XOR
%left AND
%left EQUAL NEQ
%left LT SLT SLE LE   GT GE SGT SGE
%left LSHIFT RSHIFT ARSHIFT
%left PLUS MINUS
%left TIMES DIVIDE SDIVIDE MOD SMOD
%left UMINUS NOT
%nonassoc LSQUARE
%%

program: 
| stmtlist EOF { $1 }

stmtlist:
| revstmtlist  { List.rev $1 }

/* This is needed, because if we say stmtlist := stmt stmtlist, then the parser
   needs to put all the stmts on a stack, since it can't process them until
   it parses the last one. Said stack is limited to Sys.max_array_length, which
   means than on i386, we woulddn't be able to parse a stmtlist of more than
   about 4 million.
   This is confirmed at
   http://plus.kaist.ac.kr/~shoh/ocaml/ocamllex-ocamlyacc/ocamlyacc-tutorial/sec-recursive-rules.html
 */
revstmtlist:
| revstmtlist stmt  {  $2 :: $1 }
| { [] }

stmt:
| JMP expr attrs semi { Jmp($2, $3) }
| CJMP expr COMMA expr COMMA expr attrs semi { CJmp($2, $4, $6, $7)  }
| SPECIAL STRING attrs semi { Special($2, $3)}
| lval ASSIGN expr attrs semi { Move($1, $3, $4) }
| lval EQUAL expr attrs semi { Move($1, $3, $4) }
| HALT expr attrs semi { Halt($2, $3) }
| ASSERT expr attrs semi { Assert($2, $3) } 
| LABEL ID attrs { Label(Name $2, $3) }
| ADDR INT attrs { Label(Addr $2, $3) }
| COMMENT attrs { Comment($1, $2) }




attrs:
|    { [] }
| attr attrs { $1 :: $2 }

attr:
| AT ID STRING { mk_attr $2 $3 }


lval:
| ID opttyp { 
    Scope.get_lval $1 $2
  } 

opttyp:
| { None }
| COLON typ { Some($2) } 

typ:
| styp {$1}
| QUESTION styp { TMem $2 }
| styp QUESTION styp { Array($3, $1) }

styp:
| ID { typ_of_string $1 }



letstart:
| LET ID COLON typ ASSIGN expr { (Scope.add_push $2 $4, $6) }

expr:
| LPAREN expr RPAREN { $2 }
| expr PLUS expr     { BinOp(PLUS, $1, $3) }
| expr MINUS expr    { BinOp(MINUS, $1, $3)}
| expr TIMES expr    { BinOp(TIMES, $1, $3) }
| expr DIVIDE expr   { BinOp(DIVIDE, $1, $3) }
| expr SDIVIDE expr  { BinOp(SDIVIDE, $1, $3) }
| expr MOD expr      { BinOp(MOD, $1, $3) }
| expr SMOD expr     { BinOp(SMOD, $1, $3) }
| expr LSHIFT expr   { BinOp(LSHIFT, $1, $3) }
| expr RSHIFT expr   { BinOp(RSHIFT, $1, $3) }
| expr ARSHIFT expr  { BinOp(ARSHIFT, $1, $3) }
| expr AND expr      { BinOp(AND, $1, $3) }
| expr OR expr       { BinOp(OR, $1, $3) }
| expr XOR expr      { BinOp(XOR,  $1, $3) }
| expr EQUAL expr    { BinOp(EQ, $1, $3) }
| expr EQUALEQUAL expr    { BinOp(EQ, $1, $3) }
| expr NEQ expr      { BinOp(NEQ, $1, $3) }
| expr LT expr       { BinOp(LT, $1, $3) }
| expr LE expr       { BinOp(LE,  $1, $3) }
| expr SLT expr      { BinOp(SLT, $1, $3) }
| expr SLE expr      { BinOp(SLE, $1, $3) }
/* syntactic sugar for greater than */
| expr GT expr       { BinOp(LT,  $3, $1) }
| expr GE expr       { BinOp(LE,  $3, $1) }
| expr SGT expr      { BinOp(SLT, $3, $1) }
| expr SGE expr      { BinOp(SLE, $3, $1) }
| NOT expr           { UnOp(NOT, $2) }
| MINUS expr %prec UMINUS  { UnOp(NEG, $2) }
| UNKNOWN STRING COLON typ { Unknown($2, $4) } 
| STRING             { Lab($1) } 
| lval               { Var($1) } 
| letstart IN expr   { Scope.pop();
		       let (x,y) = $1 in
		       Let(x,y, $3) } 
| ID COLON typ LPAREN expr RPAREN  
    { Cast(casttype_of_string $1, $3, $5) }	  
| TRUE               { exp_true } 
| FALSE              { exp_false }
| INT COLON typ      { Int($1, $3) } 
| expr WITH LSQUARE expr COMMA endian RSQUARE COLON typ assign expr %prec WITH
      { Store($1, $4, $11, $6, $9) }
| expr LSQUARE expr COMMA endian RSQUARE COLON typ { Load($1, $3, $5, $8) }

endian:
| EBIG  { exp_true }
| ELITTLE { exp_false }
| expr { $1 }

semi:
| SEMI { () }
| { () }

assign:
| ASSIGN {()}
| EQUAL {()}

%%

let scope_create = Scope.create
let scope_set s = Scope.cur_scope := s
let scope_default = Scope.defscope
