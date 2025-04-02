{

  open Lexing
  open Kawaparser

  exception Error of string

  let keyword_or_ident =
  let h = Hashtbl.create 17 in
  List.iter (fun (s, k) -> Hashtbl.add h s k)
    [ "print",    PRINT;
      "main",     MAIN;
      "true",     TRUE;
      "false",    FALSE;
      (* Variables *)
      "var",      VAR;
      "int",      INT_TYPE;
      "bool",     BOOL_TYPE;
      "void",     VOID_TYPE;
      (* Instructions *)
      "if",       IF;
      "else",     ELSE;
      "while",    WHILE;
      "return",   RETURN;
      (* Classes, attributs*)
      "class",     CLASS;
      "attribute", ATTRIBUTE;
      "new",       NEW;
      (* Méthodes *)
      "method",   METHOD;
      "this",     THIS;
      (* Héritage *)
      "extends",  EXTENDS;
      (* Attribut final *)
      "final",    FINAL;
      (* instanceof *)
      "instanceof", INSTANCEOF;
    ] ;
  fun s ->
    try  Hashtbl.find h s
    with Not_found -> IDENT(s)
        
}

let digit = ['0'-'9']
let number = ['-']? digit+
let alpha = ['a'-'z' 'A'-'Z']
let ident = ['a'-'z' '_'] (alpha | '_' | digit)*
  
rule token = parse
  (*| uppercase_alpha ident as id { failwith ("Error: Identifiers must not start with an uppercase letter: " ^ id) }
    *)
  | ['\n']            { new_line lexbuf; token lexbuf }
  | [' ' '\t' '\r']+  { token lexbuf }

  | "//" [^ '\n']* "\n"  { new_line lexbuf; token lexbuf }
  | "/*"                 { comment lexbuf; token lexbuf }

  | number as n  { INT(int_of_string n) }
  | ident as id  { keyword_or_ident id }

  | "+"           { PLUS }
  | "-"           { MINUS }
  | "*"           { MUL }
  | "/"           { DIV }
  | "%"           { REM }
  | "==="         { EQ_STR }
  | "=/="         { DIFF_STR }
  | "=="          { EQUAL }
  | "="           { ASSIGN }
  | "!="          { DIFF }
  | "!"           { NOT }
  | "<"           { LT }
  | "<="          { LE }
  | ">"           { GT }
  | ">="          { GE }
  | "&&"          { AND }
  | "||"          { OR }
  | "."           { DOT }
  | ","           { COMMA }
  | ";"           { SEMICOLON }
  | "("           { LPAR }
  | ")"           { RPAR }
  | "{"           { BEGIN }
  | "}"           { END }
  | "["           { LBRACKET }
  | "]"           { RBRACKET }
  | "instanceof"  { INSTANCEOF }

  | _    { raise (Error ("unknown character : " ^ lexeme lexbuf)) }
  | eof  { EOF }

and comment = parse
  | "*/" { () }
  | _    { comment lexbuf }
  | eof  { raise (Error "unterminated comment") }
