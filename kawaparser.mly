%{

  open Lexing
  open Kawa

%}

%token <int> INT
%token <bool> BOOL
%token <string> IDENT
%token INT_TYPE BOOL_TYPE VOID_TYPE
%token VOID PRINT VAR
%token MAIN TRUE FALSE
%token LPAR RPAR BEGIN END SEMICOLON DOT COMMA
%token IF ELSE WHILE RETURN 
%token PLUS MINUS MUL DIFF EQUAL ASSIGN LE LT GE GT AND OR DIV REM NOT 
%token CLASS ATTRIBUTE NEW THIS METHOD EXTENDS FINAL
%token LBRACKET RBRACKET
%token EQ_STR DIFF_STR
%token INSTANCEOF
%token EOF 

%start program
%type <Kawa.program> program  

%nonassoc MEM_A
%nonassoc INSTANCEOF
%left OR
%left AND
%nonassoc DIFF NEQ LT LE GT GE EQUAL EQ_STR DIFF_STR
%left PLUS MINUS 
%left MUL DIV REM
%right OPP
%nonassoc LPAR RPAR
%nonassoc LBRACKET
%nonassoc ASSIGN
%nonassoc DOT
%%


program:
| decls=list(var_decl) cls=list(class_def) MAIN BEGIN instructions=list(instruction) END EOF
    { { globals = List.flatten decls; classes = cls; main = instructions } }
;

class_def:
| CLASS ident=IDENT BEGIN att=list(attribute_decl) m=list(method_def) END
    { {class_name=ident; attributes=att; methods=m; parent=None} }
| CLASS ident=IDENT EXTENDS parent=IDENT BEGIN att=list(attribute_decl) m=list(method_def) END
    { {class_name=ident; attributes=att; methods=m; parent=Some(parent)} }
;

var_decl:
| VAR t=data_type ids=separated_list(COMMA, IDENT) ASSIGN init=expression SEMICOLON
    { List.map (fun id -> (id, t, Some init)) ids }
| VAR t=data_type ids=separated_list(COMMA, IDENT) SEMICOLON
    { List.map (fun id -> (id, t, None)) ids }
;

attribute_decl:
| ATTRIBUTE FINAL t=data_type ident=IDENT ASSIGN init=expression SEMICOLON { (ident, t, true, Some init) }  
| ATTRIBUTE FINAL t=data_type ident=IDENT SEMICOLON { (ident, t, true, None) }
| ATTRIBUTE t=data_type ident=IDENT ASSIGN init=expression SEMICOLON { (ident, t, false, Some init) }   
| ATTRIBUTE t=data_type ident=IDENT SEMICOLON { (ident, t, false, None) }
;

data_type:
| INT_TYPE    { TInt }
| BOOL_TYPE   { TBool }
| VOID_TYPE   { TVoid }
| ident=IDENT { TClass(ident) }
| t=data_type LBRACKET RBRACKET { TArray(t) } 
;

method_def:
| METHOD return_type=data_type ident=IDENT LPAR params=separated_list(COMMA, param_decl) RPAR BEGIN locals=list(var_decl) body=list(instruction) END
    { {method_name=ident; return=return_type; params=params; locals=List.flatten locals; code=body} }
;

param_decl:
| t=data_type ident=IDENT { (ident, t) }
;

expression:
| n=INT { Int(n) }
| TRUE  { Bool(true) } 
| FALSE { Bool(false) }
| THIS  { This }
| mem=mem_access     %prec MEM_A    { Get(mem) }
| u=uop e=expression %prec OPP      { Unop(u, e) }
| e1=expression b=bop e2=expression { Binop(b, e1, e2) }
| LPAR e=expression RPAR { e }
| NEW ident=IDENT        { New(ident) }
| NEW ident=IDENT LPAR args=separated_list(COMMA, expression) RPAR                 { NewCstr(ident, args) }
| obj=expression DOT ident=IDENT LPAR args=separated_list(COMMA, expression) RPAR  { MethCall(obj, ident, args) } 
| NEW t=data_type LBRACKET size=expression RBRACKET   %prec LBRACKET               { ArrayCreate(t, size)  }
| array=IDENT LBRACKET index=expression RBRACKET      %prec LBRACKET               { ArrayAccess(array, index) } 
| array=IDENT LBRACKET index=expression RBRACKET ASSIGN value=expression           { ArrayAssign(array, index, value) } 
| e=expression INSTANCEOF t=data_type %prec INSTANCEOF                             { InstanceOf(e, t) }
;

mem_access:
| ident=IDENT { Var(ident) }
| obj=expression DOT ident=IDENT %prec DOT { Field(obj, ident) }
;

instruction:
| PRINT LPAR e=expression RPAR SEMICOLON       { Print(e) }
| mem=mem_access ASSIGN e=expression SEMICOLON { Set(mem, e) }
| IF LPAR cond=expression RPAR BEGIN then_instrs=list(instruction) END ELSE BEGIN else_instrs=list(instruction) END 
    { If(cond, then_instrs, else_instrs) }
| WHILE LPAR cond=expression RPAR BEGIN body=list(instruction) END 
    { While(cond, body) }
| RETURN e=expression SEMICOLON { Return(e) }
| e=expression SEMICOLON        { Expr(e) }
;

uop:
| MINUS { Opp }
| NOT   { Not }
;

%inline bop:
| PLUS     { Add } 
| MINUS    { Sub }
| MUL      { Mul }
| DIV      { Div }
| REM      { Rem }
| EQUAL    { Eq  }
| ASSIGN   { Ass }
| DIFF     { Neq }
| EQ_STR   { Eq_str   }
| DIFF_STR { Diff_str }
| LE       { Le  }
| LT       { Lt  }
| GE       { Ge  }
| GT       { Gt  }
| AND      { And }
| OR       { Or  }
;
