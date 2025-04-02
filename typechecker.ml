open Kawa

exception Error of string
let error s = raise (Error s)
let type_error ty_actual ty_expected =
  error (Printf.sprintf "expected %s, got %s"
           (typ_to_string ty_expected) (typ_to_string ty_actual))

module Env = Map.Make(String)
type tenv = typ Env.t


(* Trouver un attribut dans la classe ou ses ancêtres *)
let rec find_attribute p class_name att =
  (* Trouve la définition de la classe dans la liste des classes du programme *)
  match List.find_opt (fun cls -> cls.class_name = class_name) p.classes with
  | Some cls -> (
    (* Chercher dans les définitions de la classe actuelle *)
      match List.find_opt (fun (name, _, _, _) -> name = att) cls.attributes with
      | Some (_, attr_typ, is_final, _) -> Some (attr_typ, is_final)
      | None -> (
          (* Regarder dans la classe parent si pas trouvé*)
          match cls.parent with
          | Some parent -> find_attribute p parent att
          | None -> None
        )
    )
  | None -> None

(* Vérifie la compatibilité des types pour l'égalité structurelle *)
let rec typ_structural_eq t1 t2 =
  match t1, t2 with
    | TInt, TInt -> true
    | TBool, TBool -> true
    | TClass c1, TClass c2 -> true 
    | TArray t1, TArray t2 -> typ_structural_eq t1 t2
    | _ -> false
  
let add_env l tenv =
  List.fold_left (fun env (x, t) -> Env.add x t env) tenv l

(* Cas où l'on déclare des variables en série *)
let add_env_multiple ids typ tenv =
  List.fold_left (fun env id -> Env.add id typ env) tenv ids

    
let typecheck_prog p =
  (* Ajusté pour le cas où l'on déclare des variables en série *)
  let tenv = 
    List.fold_left (fun env (name, typ, _) ->
      Env.add name typ env
    ) Env.empty p.globals  
  in

(* Détermine si un type est un sous-type d'un autre *)
let rec is_subtype t1 t2 =
  match t1, t2 with
    | _, _ when t1 = t2 -> true
    | TClass c1, TClass c2 -> (
        match List.find_opt (fun cls -> cls.class_name = c1) p.classes with
        | Some cls -> (
            match cls.parent with
            (* Si c1 a un parent on vérifie récursivement si le parent est un sous-type de t2 *)
            | Some parent -> is_subtype (TClass parent) t2
            | None -> false
          )
        | None -> false
      )
    | _ -> false
in
    
let rec check e typ tenv =
  let typ_e = type_expr e tenv in
  if not (is_subtype typ_e typ) then type_error typ_e typ
    
and type_expr e tenv = 
  match e with
  | Int _  -> TInt
  | Bool _ -> TBool
  | Unop (op, e) -> (
      match op, type_expr e tenv with
        | Opp, TInt -> TInt
        | Not, TBool -> TBool
        | _, typ -> error (Printf.sprintf "Unary operator type mismatch: %s" (typ_to_string typ))
    )
  | Binop (Ass, ArrayAccess (array, index), value) ->
      let array_type = type_expr (Get (Var array)) tenv in (* Type du tableau *)
      let index_type = type_expr index tenv in
      let value_type = type_expr value tenv in
      if index_type <> TInt then error "Array index must be an integer"
      else (
        match array_type with
          | TArray t when value_type = t -> TVoid
          | TArray _ -> error "Type mismatch in array assignment"
          | _ -> error "Attempted to assign to a non-array type"
      )
  | Binop (op, e1, e2) -> (
    match op, type_expr e1 tenv, type_expr e2 tenv with
      | (Add | Sub | Mul | Div | Rem), TInt, TInt -> TInt
      | (Lt | Le | Gt | Ge), TInt, TInt -> TBool
      | (Eq | Neq), typ1, typ2 when typ1 = typ2 -> TBool
      | (Eq_str | Diff_str), typ1, typ2 when typ_structural_eq typ1 typ2 -> TBool
      | (And | Or), TBool, TBool -> TBool
      | _, typ1, typ2 -> 
          error (Printf.sprintf "Binary operator type mismatch: %s, %s"
                  (typ_to_string typ1) (typ_to_string typ2))
    )
  | Get m -> type_mem_access m tenv         
  | New s -> 
      if List.exists (fun cls -> cls.class_name = s) p.classes then 
        TClass s
      else
        error ("classe inconnue " ^ s)
  | NewCstr (class_name, args) -> (
      match List.find_opt (fun cls -> cls.class_name = class_name) p.classes with
        | Some cls -> (
            (* Trouve le constructeur de la classe *)
            match List.find_opt (fun m -> m.method_name = "constructor") cls.methods with
            | Some constructor -> (
                let expected_params = constructor.params in
                (* Vérifie que le nombre d'arguments fournis correspond à celui du constructeur *)
                if List.length expected_params <> List.length args then
                  error (Printf.sprintf "Constructor of class '%s' expects %d arguments, but %d were given"
                            class_name (List.length expected_params) (List.length args));
                (* Vérifie les types de chaque argument par rapport au type attendu pour le paramètre 
                   correspondant *)
                List.iter2 
                  (fun (_, param_type) arg_expr ->
                    let arg_type = type_expr arg_expr tenv in
                    if arg_type <> param_type then type_error arg_type param_type)
                  expected_params args;
                TClass class_name
                )
            | None -> error (Printf.sprintf "Class '%s' has no constructor defined" class_name)
          )
        | None -> error (Printf.sprintf "Undefined class: %s" class_name)
    )    
  | MethCall (obj_expr, method_name, args) -> (
      match type_expr obj_expr tenv with
      | TClass class_name -> (
          match List.find_opt (fun cls -> cls.class_name = class_name) p.classes with
          | Some cls -> (
              match List.find_opt (fun m -> m.method_name = method_name) cls.methods with
              | Some method_def -> (
                  (* Vérifie que le nombre d'arguments correspond à celui attendu par la méthode *)
                  if List.length method_def.params <> List.length args then
                    error (Printf.sprintf "Method '%s' expects %d arguments, but %d were given"
                            method_name (List.length method_def.params) (List.length args));
                  (* Vérifie le type de chaque argument par rapport au type attendu *)
                  List.iter2
                    (fun (_, param_type) arg_expr ->
                      let arg_type = type_expr arg_expr tenv in
                      if not (is_subtype arg_type param_type) then
                        type_error arg_type param_type)
                    method_def.params args;
                  method_def.return
                )
              | None -> error (Printf.sprintf "Undefined method '%s' in class '%s'" method_name class_name)
            )
          | None -> error (Printf.sprintf "Undefined class '%s'" class_name)
        )
      | _ -> error (Printf.sprintf "Method '%s' called on non-object" method_name)
    )
  | This -> (
      match Env.find_opt "this" tenv with
        | Some t -> t
        | None -> error "Use of 'this' outside of a class or method"
    )
  | ArrayCreate (t, size) ->
      let size_type = type_expr size tenv in
      if size_type <> TInt then error "Array size must be an integer"
      else TArray t
  | ArrayAccess (array, index) ->
      let array_type = type_expr (Get (Var array)) tenv in
      let index_type = type_expr index tenv in
      if index_type <> TInt then error "Array index must be an integer"
      else (
        match array_type with
          | TArray t -> t
          | _ -> error "Attempted to access a non-array type"
      )
  | ArrayAssign (array, index, value) ->
      let array_type = type_expr (Get (Var array)) tenv in
      let index_type = type_expr index tenv in
      let value_type = type_expr value tenv in
      if index_type <> TInt then error "Array index must be an integer"
      else (
        match array_type with
        | TArray t when value_type = t -> TVoid
        | TArray _ -> error "Type mismatch in array assignment"
        | _ -> error "Attempted to assign to a non-array type"
      )
  | InstanceOf (obj_expr, typ) ->
    let obj_type = type_expr obj_expr tenv in
    (match obj_type with
      | TClass _ | TVoid -> TBool  (* instanceof retourne toujours un booléen *)
      | _ -> error "The left-hand side of 'instanceof' must be an object or void")
  | _ -> failwith "case not implemented in type_expr"  

and type_mem_access m tenv = match m with
  | Var x -> (
      try Env.find x tenv
      with Not_found -> error (Printf.sprintf "Undefined variable: %s" x)
    )
  | Field (obj_expr, attr) -> (
      match type_expr obj_expr tenv with
        | TClass class_name -> (
            match find_attribute p class_name attr with
              | Some (attr_typ, _) -> attr_typ
              | None -> error (Printf.sprintf "Undefined attribute '%s' in class '%s'" attr class_name)
          )
        | _ -> error (Printf.sprintf "Field '%s' accessed on non-object" attr)
    )
  | _ -> failwith "case not implemented in type_mem_access"
in

let rec check_instr i ret tenv in_constructor = match i with
  | Print e -> check e TInt tenv
  | Expr e -> check e TVoid tenv  
  | Return e -> (
      if ret = TVoid then error "Return statement in a void method"
      else check e ret tenv
    )
  | Set (mem, e) -> (
      let expected_type = type_mem_access mem tenv in
      let actual_type = type_expr e tenv in
      if not (is_subtype actual_type expected_type) then
        type_error actual_type expected_type
    )
  | If (cond, then_branch, else_branch) ->
      check cond TBool tenv;
      check_seq then_branch ret tenv in_constructor;
      check_seq else_branch ret tenv in_constructor
  | While (cond, body) ->
      check cond TBool tenv;
      check_seq body ret tenv in_constructor
  | _ -> failwith "case not implemented in check_instr"

and check_seq s ret tenv in_constructor =
  List.iter (fun i -> check_instr i ret tenv in_constructor) s
in

  
(* Vérification de chaque méthode de classe *)
let check_mdef cls mdef =
  let in_constructor = (mdef.method_name = "constructor") in
  let locals = List.map (fun (name, typ, _) -> (name, typ)) mdef.locals in
  let method_tenv =
    Env.add "this" (TClass cls.class_name)
      (add_env mdef.params (add_env locals tenv)) (* On ajoute les variables locales et des paramètres *)
  in
  check_seq mdef.code mdef.return method_tenv in_constructor
in

let check_class cls =
  List.iter (fun mdef -> check_mdef cls mdef) cls.methods
in

(* Vérification des classes *)
List.iter check_class p.classes;

check_seq p.main TVoid tenv false
