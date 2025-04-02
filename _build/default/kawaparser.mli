
(* The type of tokens. *)

type token = 
  | WHILE
  | VOID_TYPE
  | VOID
  | VAR
  | TRUE
  | THIS
  | SEMICOLON
  | RPAR
  | RETURN
  | REM
  | RBRACKET
  | PRINT
  | PLUS
  | OR
  | NOT
  | NEW
  | MUL
  | MINUS
  | METHOD
  | MAIN
  | LT
  | LPAR
  | LE
  | LBRACKET
  | INT_TYPE
  | INT of (int)
  | INSTANCEOF
  | IF
  | IDENT of (string)
  | GT
  | GE
  | FINAL
  | FALSE
  | EXTENDS
  | EQ_STR
  | EQUAL
  | EOF
  | END
  | ELSE
  | DOT
  | DIV
  | DIFF_STR
  | DIFF
  | COMMA
  | CLASS
  | BOOL_TYPE
  | BOOL of (bool)
  | BEGIN
  | ATTRIBUTE
  | ASSIGN
  | AND

(* This exception is raised by the monolithic API functions. *)

exception Error

(* The monolithic API. *)

val program: (Lexing.lexbuf -> token) -> Lexing.lexbuf -> (Kawa.program)
