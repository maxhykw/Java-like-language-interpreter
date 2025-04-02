open Kawa

type value =
  | VInt of int
  | VBool of bool
  | VObj of obj
  | VArray of value array 
  | Null

and obj = {
  cls:    string;
  fields: (string, value) Hashtbl.t;
}

exception Error of string
exception Return of value


let rec find_attribute p class_name attr =
  match List.find_opt (fun c -> c.class_name = class_name) p.classes with
  | Some cls_def -> (
      match List.find_opt (fun (name, _, _, _) -> name = attr) cls_def.attributes with
      | Some attr_def -> attr_def
      | None -> (
          match cls_def.parent with
          | Some parent_name -> find_attribute p parent_name attr
          | None -> raise Not_found
        )
    )
  | None -> raise (Error (Printf.sprintf "Undefined class '%s'" class_name))


(* Vérifie si le type dynamique de l'objet est un sous-type de `typ` *)
let rec is_subtype p cls_name typ = 
  match typ with
    | TClass t -> (
        (* La classe actuelle correspond au type cible *)
        if cls_name = t then true
        else
          (* Sinon on cherche sa définition dans la liste des classes *)
          match List.find_opt (fun cls -> cls.class_name = cls_name) p.classes with
            | Some cls -> (
                match cls.parent with
                | Some parent -> is_subtype p parent typ
                | None -> false
              )
            | None -> false
      )
    | _ -> false

(* Fonction d'égalité structurelle *)
let rec structural_eq v1 v2 =
  match v1, v2 with
    | VInt n1, VInt n2 -> n1 = n2
    | VBool b1, VBool b2 -> b1 = b2
    | VObj o1, VObj o2 ->
        o1.cls = o2.cls &&
        (* Vérifie récursivement si tous les champs des deux objets sont égaux *)
        Hashtbl.fold (fun field value acc ->
          acc && (try structural_eq value (Hashtbl.find o2.fields field) with Not_found -> false)
        ) o1.fields true
    | VArray a1, VArray a2 ->
        (* Les deux tableaux doivent avoir la même longueur 
           et leurs éléments doivent être structurellement égaux *)
        Array.length a1 = Array.length a2 &&
        Array.for_all2 structural_eq a1 a2
    (* On admet que Null === Null*)
    | Null, Null -> true
    | _, _ -> false

(* Fonction d'inégalité structurelle *)
let structural_diff v1 v2 = not (structural_eq v1 v2)


let exec_prog (p: program): unit =
  let env = Hashtbl.create 16 in

  let rec exec_seq s lenv =
    let rec evali e = match eval e with
      | VInt n -> n
      | _ -> assert false
    and evalb e = match eval e with
      | VBool b -> b
      | _ -> assert false
    and evalo e = match eval e with
      | VObj o ->  o
      | _ -> assert false

    and eval (e: expr): value = 
      match e with
      | Int n  -> VInt n
      | Bool b -> VBool b
      | Unop (op, e) -> (
          match op, eval e with
          | Opp, VInt n -> VInt (-n) 
          | Not, VBool b -> VBool (not b) 
          | _, _ -> raise (Error "Type mismatch in unary operation")
        )

      | Binop (op, e1, e2) -> (
          let v1 = eval e1 in
          match op, v1 with
          (* les operations && et || sont paresseuses *)
          | And, VBool b1 -> if not b1 then VBool false else eval e2
          | Or, VBool b1 -> if b1 then VBool true else eval e2
          | Ass, VArray arr -> (
              match e1, eval e2 with
                | ArrayAccess (arr, idx), v -> (
                    match eval (Get (Var arr)), eval idx with
                      (* Indice dans les bornes *)
                      | VArray arr, VInt i when i >= 0 && i < Array.length arr -> (
                          (* Assigne la nouvelle valeur au tableau à l'indice spécifié *)
                          arr.(i) <- v;
                          v
                        )
                      | VArray _, VInt _ -> raise (Error "Array index out of bounds")
                      | _, _ -> raise (Error "Invalid array access or assignment")
                  )
                | _, _ -> raise (Error "Left-hand side of assignment is not an array access")
              )
          | _, _ -> (
            match op, v1, eval e2 with
              | Add, VInt n1, VInt n2 -> VInt (n1 + n2)
              | Sub, VInt n1, VInt n2 -> VInt (n1 - n2)
              | Mul, VInt n1, VInt n2 -> VInt (n1 * n2)
              | Div, VInt n1, VInt n2 -> if n2 = 0 then raise (Error "Division by zero") else VInt (n1 / n2)
              | Rem, VInt n1, VInt n2 -> if n2 = 0 then raise (Error "Modulo by zero") else VInt (n1 mod n2)
              | Eq, v1, v2       -> VBool (v1 = v2)
              | Neq, v1, v2      -> VBool (v1 <> v2)
              | Eq_str, v1, v2   -> VBool (structural_eq v1 v2)
              | Diff_str, v1, v2 -> VBool (structural_diff v1 v2)
              | Le, VInt n1, VInt n2 -> VBool (n1 <= n2)
              | Lt, VInt n1, VInt n2 -> VBool (n1 < n2)
              | Ge, VInt n1, VInt n2 -> VBool (n1 >= n2)
              | Gt, VInt n1, VInt n2 -> VBool (n1 > n2)   
              | _, _, _ -> raise (Error "Type mismatch in binary operation")
            )
        )
      | Get mem_access -> (
          match mem_access with 
          | Var x -> (
              try Hashtbl.find lenv x
              with Not_found -> (
                try Hashtbl.find env x 
                with Not_found -> raise (Error (Printf.sprintf "Undefined variable: %s" x))
              )
            )
          | Field (obj_expr, attr) -> (
              match evalo obj_expr with
              | { cls; fields } -> (
                (* Recherche du champ dans les champs de l'objet *)  
                try 
                    match Hashtbl.find fields attr with
                    | Null -> raise (Error (Printf.sprintf "Field '%s' in class '%s' is not initialized" attr cls))
                    | value -> value
                  with Not_found -> raise (Error (Printf.sprintf "Undefined field: %s in class '%s'" attr cls))
                )
              | _ -> raise (Error "Expected object in field access")
            )
        )
      | New class_name -> (
          match List.find_opt (fun c -> c.class_name = class_name) p.classes with
          | Some class_def ->
              let obj = { cls = class_name; fields = Hashtbl.create 16 } in
              (* Initialiser les attributs avec leurs valeurs par défaut *)
              List.iter (fun (name, _, _, init_opt) ->
                let value = match init_opt with
                  | Some expr -> eval expr  
                  | None -> Null            
                in
                Hashtbl.add obj.fields name value
              ) class_def.attributes;
              VObj obj
          | None -> raise (Error (Printf.sprintf "Undefined class '%s'" class_name))
        )
      | NewCstr (class_name, args) ->
          let obj = evalo (New class_name) in
          let arg_values = List.map eval args in
          (* Appelle explicitement le constructeur (de la classe) *)
          let _ = eval_call "constructor" (VObj obj) arg_values in
          VObj obj
      | This -> (
          try Hashtbl.find lenv "this"
          with Not_found -> raise (Error "Undefined 'this'")
        )
      | MethCall (obj_expr, method_name, args) -> (
          let obj_value = eval obj_expr in
          let arg_values = List.map eval args in
          match obj_value with
          | VObj _ -> eval_call method_name obj_value arg_values
          | _ -> raise (Error "Method call on non-object")
        )
      | ArrayCreate (t, size) -> (
          match eval size with
          | VInt n when n >= 0 -> VArray (Array.make n Null)
          | VInt _ -> raise (Error "Array size must be non-negative")
          | _ -> raise (Error "Array size must be an integer")
        )
      | ArrayAccess (array, index) -> (
        match eval (Get (Var array)), eval index with
          | VArray arr, VInt i when i >= 0 && i < Array.length arr -> (
              match arr.(i) with
              | Null -> raise (Error (Printf.sprintf "Array element at index %d is not initialized" i))
              | value -> value
            )
          | VArray _, VInt _ -> raise (Error "Array index out of bounds")
          | _, _ -> raise (Error "Invalid array access")
        )
      | ArrayAssign (array_name, index, value) -> (
          match Hashtbl.find_opt lenv array_name, eval index with
          | Some (VArray arr), VInt i when i >= 0 && i < Array.length arr ->
              arr.(i) <- eval value;
              Null
          | Some (VArray _), VInt _ -> raise (Error "Array index out of bounds")
          | _, _ -> raise (Error "Invalid array assignment")
        )
      | InstanceOf (obj_expr, typ) -> (
          match eval obj_expr with
            | VObj obj -> VBool (is_subtype p obj.cls typ)
            | _ -> VBool false  (* Non-objets retournent false pour instanceof *)
          )
      | _ -> failwith "case not implemented in eval"

    and eval_call f this args =
      match this with
      | VObj { cls; _ } -> (
          match List.find_opt (fun c -> c.class_name = cls) p.classes with
          | Some class_def -> (
              match List.find_opt (fun m -> m.method_name = f) class_def.methods with
              | Some mdef -> (
                  let lenv = Hashtbl.create 16 in
                  Hashtbl.add lenv "this" this;
                  (* Initialisation des paramètres *)
                  List.iter2
                    (fun (param_name, _) arg_value -> Hashtbl.add lenv param_name arg_value)
                    mdef.params args;
                  (* Initialisation des variables locales *)
                  List.iter (fun (local_name, _, init_opt) ->
                    let value = match init_opt with
                      | Some expr -> eval expr 
                      | None -> Null
                    in
                    Hashtbl.add lenv local_name value
                  ) mdef.locals;
                  try
                    exec_seq mdef.code lenv;
                    Null
                  with Return value -> value
              )
              | None -> raise (Error (Printf.sprintf "Undefined method '%s' in class '%s'" f cls))
          )
          | None -> raise (Error (Printf.sprintf "Undefined class '%s'" cls))
      )
      | _ -> raise (Error (Printf.sprintf "Cannot call method '%s' on non-object" f))
    in
    (* Initialisation des variables globales *)
    List.iter (fun (name, _, init_opt) ->
      let value = match init_opt with
        | Some expr -> eval expr (* Évaluation de l'expression initiale *)
        | None -> Null           (* Valeur non initialisée *)
      in
      Hashtbl.add env name value
    ) p.globals;

    let rec exec (i: instr): unit = match i with
      | Print e -> Printf.printf "%d\n" (evali e)
      | Expr e -> let _ = eval e in ()  
      | Return e -> raise (Return (eval e))
      | If (cond, then_branch, else_branch) -> 
          if evalb cond then exec_seq then_branch else exec_seq else_branch
      | While (cond, body) -> 
          while evalb cond do
            exec_seq body
          done
      | Set (mem, e) -> (
          match mem with
          | Var x -> Hashtbl.replace lenv x (eval e)
          | Field (obj_expr, attr) -> (
              match evalo obj_expr with
              | { cls; fields } -> (
                try
                  let value = eval e in
                  (* Trouver la définition de l'attribut dans la classe ou ses ancêtres *)
                  let (_, _, is_final, _) = find_attribute p cls attr in
                  let current_value = Hashtbl.find_opt fields attr in

                  (* Vérification des contraintes 'final' *)
                  if is_final && current_value <> Some Null then
                    raise (Error (Printf.sprintf "Cannot reassign final attribute '%s' in class '%s'" attr cls));
                  
                    (* Assignation de la valeur *)
                  Hashtbl.replace fields attr value
                with
                | Not_found -> raise (Error (Printf.sprintf "Undefined field '%s' in class '%s'" attr cls))
              )
            | _ -> raise (Error "Cannot assign to non-object field")
           )
        )
      | _ -> failwith "case not implemented in exec"

    and exec_seq s = 
      List.iter exec s
    in

    exec_seq s
  in
  
  exec_seq p.main (Hashtbl.create 1)
