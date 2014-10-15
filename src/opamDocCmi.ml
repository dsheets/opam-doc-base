(*
 * Copyright (c) 2014 Leo White <lpw25@cl.cam.ac.uk>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open OpamDocPath
open Documentation
open Asttypes
open Parsetree
open Types
open OpamDocTypes

module Name = OpamDocName

let map_opt f = function
  | None -> None
  | Some x -> Some (f x)

let iter_opt f = function
  | None -> ()
  | Some x -> f x

let rec read_style : Documentation.style_kind -> style = function
  | SK_bold -> Bold
  | SK_italic -> Italic
  | SK_emphasize -> Emphasize
  | SK_center -> Center
  | SK_left -> Left
  | SK_right -> Right
  | SK_superscript -> Superscript
  | SK_subscript -> Subscript
  | SK_custom s -> Custom s

and read_text_element res : Documentation.text_element -> text = function
  | Raw s -> [Raw s]
  | Code s -> [Code s]
  | PreCode s -> [PreCode s]
  | Verbatim s -> [Verbatim s]
  | Style(sk, txt) -> [Style(read_style sk, read_text res txt)]
  | List l -> [List(List.map (read_text res) l)]
  | Enum l -> [Enum(List.map (read_text res) l)]
  | Newline -> [Newline]
  | Title(i, l, txt) -> [Title (i, l, read_text res txt)]
  | Ref(RK_module, s, txt) -> begin
      match lookup_module res s, txt with
      | None, None -> [Raw s]
      | None, Some txt -> read_text res txt
      | Some p, None -> [Ref(Module p, None)]
      | Some p, Some txt -> [Ref(Module p, Some (read_text res txt))]
    end
  | Ref(RK_module_type, s, txt) -> begin
      match lookup_module_type res s, txt with
      | None, None -> [Raw s]
      | None, Some txt -> read_text res txt
      | Some p, None -> [Ref(ModuleType p, None)]
      | Some p, Some txt -> [Ref(ModuleType p, Some (read_text res txt))]
    end
  | Ref(RK_type, s, txt) -> begin
      match lookup_type res s, txt with
      | None, None -> [Raw s]
      | None, Some txt -> read_text res txt
      | Some p, None -> [Ref(Type p, None)]
      | Some p, Some txt -> [Ref(Type p, Some (read_text res txt))]
    end
  | Ref(RK_value, s, txt) -> begin
      match lookup_value res s, txt with
      | None, None -> [Raw s]
      | None, Some txt -> read_text res txt
      | Some p, None -> [Ref(Val p, None)]
      | Some p, Some txt -> [Ref(Val p, Some (read_text res txt))]
    end
  | Ref(RK_element, s, txt) -> begin
      match lookup_value res s, txt with
      | None, None -> [Raw s]
      | None, Some txt -> read_text res txt
      | Some p, None -> [Ref(Val p, None)]
      | Some p, Some txt -> [Ref(Val p, Some (read_text res txt))]
    end
  | Ref(RK_link, uri, txt) -> begin
      match txt with
      | None   -> [Ref (Link uri, None)]
      | Some t -> [Ref (Link uri, Some (read_text res t))]
    end
  | Ref(_, s, _)  -> [TEXT_todo ("ref:"^s)]
  | Special_ref _ -> [TEXT_todo "special-ref"]
  | Target (target, code) -> [Target (target, code)]

and read_text res txt =
  List.concat (List.map (read_text_element res) txt)

let read_tag res: Documentation.tag -> tag = function
  | Author s -> Author s
  | Version v -> Version v
  | See (r, t) -> See (r, read_text res t)
  | Since s -> Since s
  | Before (s, t) -> Before (s, read_text res t)
  | Deprecated t -> Deprecated (read_text res t)
  | Param (s, t) -> Param (s, read_text res t)
  | Raised_exception (s, t) -> Raise (s, read_text res t)
  | Return_value t -> Return (read_text res t)
  | Custom (s, t) -> Tag (s, read_text res t)

let read_documentation res : Documentation.t -> text * tag list = function
  | Cinfo(txt, tags) -> read_text res txt, List.map (read_tag res) tags
  | Cstop ->
      (* FIXME: need a better story for handling ocamldoc stop comments *)
      [], []

let rec read_attributes res : Parsetree.attributes -> doc = function
  | ({txt = "doc"}, PDoc(d, _)) :: rest ->
      let rec loop = function
        | ({txt = "doc"}, PDoc(d, _)) :: rest ->
            let d, t = read_documentation res d in
            let rest, tags = loop rest in
            (Newline :: d @ rest), t @ tags
        | _ :: rest -> loop rest
        | [] -> [], []
      in
      let d, t = read_documentation res d in
      let rest, tags = loop rest in
      { info = d @ rest;
        tags = t @ tags; }
  | _ :: rest -> read_attributes res rest
  | [] -> { info = []; tags = []; }

let read_label lbl =
  let len = String.length lbl in
  if len = 0 then None
  else if lbl.[0] = '?' then
    Some (Default (String.sub lbl 1 (len - 1)))
  else Some (Label lbl)

(* Handle type variable names *)

let names = ref []
let name_counter = ref 0
let used_names = ref []

let reset_names () = names := []; name_counter := 0; used_names := []

let add_used_name = function
  | Some name ->
      if not (List.mem name !used_names) then
        used_names := name :: !used_names
  | None -> ()

let rec new_name () =
  let name =
    if !name_counter < 26
    then String.make 1 (Char.chr(97 + !name_counter))
    else String.make 1 (Char.chr(97 + !name_counter mod 26)) ^
         string_of_int(!name_counter / 26) in
  incr name_counter;
  if List.mem name !used_names
  || List.exists (fun (_, name') -> name = name') !names
  then new_name ()
  else name

let name_of_type (t : Types.type_expr) =
  try List.assq t !names with Not_found ->
    let name =
      match t.desc with
      | Tvar (Some name) | Tunivar (Some name) ->
          let current_name = ref name in
          let i = ref 0 in
          while List.exists (fun (_, name') -> !current_name = name') !names do
            current_name := name ^ (string_of_int !i);
            i := !i + 1;
          done;
          !current_name
      | _ -> new_name ()
    in
    if name <> "_" then names := (t, name) :: !names;
    name

(* Handle recursive types *)

let aliased = ref []

let reset_aliased () = aliased := []

let is_aliased ty = List.memq ty !aliased

let add_alias ty =
  if not (is_aliased ty) then aliased := ty :: !aliased

let aliasable (ty : Types.type_expr) =
  match ty.desc with
  | Tvar _ -> false
  | _ -> true

let mark_type ty =
  let rec loop visited ty =
    let ty = Btype.repr ty in
    if List.memq ty visited && aliasable ty then add_alias ty else
      let visited = ty :: visited in
      match ty.desc with
      | Tvar name -> add_used_name name
      | Tarrow(_, ty1, ty2, _) ->
          loop visited ty1;
          loop visited ty2
      | Ttuple tyl -> List.iter (loop visited) tyl
      | Tconstr(p, tyl, _) ->
          List.iter (loop visited) tyl
      | Tsubst ty -> loop visited ty
      | _ -> ()
  in
  loop [] ty

let mark_type_kind = function
  | Type_abstract -> ()
  | Type_variant cds ->
      List.iter
        (fun cd ->
           List.iter mark_type cd.cd_args;
           iter_opt mark_type cd.cd_res)
        cds
  | Type_record(lds, _) ->
      List.iter (fun ld -> mark_type ld.ld_type) lds
  | Type_open -> ()

let rec read_type_expr res (typ : Types.type_expr) : type_expr =
  let typ = Btype.repr typ in
  if List.mem_assq typ !names then Var (name_of_type typ)
  else begin
    let alias =
      if is_aliased typ && aliasable typ then Some (name_of_type typ)
      else None
    in
    let typ =
      match typ.desc with
      | Tvar _ -> Var (name_of_type typ)
      | Tarrow(lbl, arg, ret, _) ->
          let label = read_label lbl in
          let typ = match label with
            | None
            | Some (Label _)   -> read_type_expr res arg
            | Some (Default _) ->
                let is_option t =
                  Name.Type.to_string (Type.name t) = "option"
                in
                match read_type_expr res arg with
                | Constr(Known t, [x]) when is_option t -> x
                | Constr(Unknown "option", [x]) -> x
                | _ -> assert false (* Optional labels are *always* optional *)
          in
          Arrow(label, typ, read_type_expr res ret)
      | Ttuple typs -> Tuple (List.map (read_type_expr res) typs)
      | Tconstr(p, typs, _) ->
          let p =
            match find_type res p with
            | None -> Unknown (Path.name p)
            | Some p -> Known p
          in
          let typs = List.map (read_type_expr res) typs in
          Constr(p, typs)
      | Tsubst typ -> read_type_expr res typ
      | _ -> TYPE_EXPR_todo (name_of_type typ)
    in
    match alias with
    | Some name -> Alias(typ, name)
    | None -> typ
  end

let read_type_scheme res (typ : Types.type_expr) : type_expr =
  reset_names ();
  reset_aliased ();
  mark_type typ;
  read_type_expr res typ

let read_value_description res id (v : Types.value_description): val_ =
  { name = Name.Value.of_string (Ident.name id);
    doc = read_attributes res v.val_attributes;
    type_ = read_type_scheme res v.val_type; }

let rec read_type_param res (typ : Types.type_expr) =
  match read_type_expr res typ with
  | Var v -> v
  | _ -> "todo"

let read_constructor_declaration res (cd : Types.constructor_declaration)
  : constructor =
  { name = Name.Constructor.of_string (Ident.name cd.cd_id);
    doc = read_attributes res cd.cd_attributes;
    args = List.map (read_type_expr res) cd.cd_args;
    ret = map_opt (read_type_expr res) cd.cd_res; }

let opt_iter f = function None -> () | Some x -> f x

let read_extension_constructor res id (e: Types.extension_constructor): exn_ =
  reset_names ();
  reset_aliased ();
  List.iter mark_type e.ext_args;
  opt_iter mark_type e.ext_ret_type;
  { name = Name.Exn.of_string (Ident.name id);
    doc = read_attributes res e.ext_attributes;
    args = List.map (read_type_expr res) e.ext_args;
    ret = map_opt (read_type_expr res) e.ext_ret_type; }

let read_label_declaration res (ld : Types.label_declaration) : field =
  { name = Name.Field.of_string (Ident.name ld.ld_id);
    doc = read_attributes res ld.ld_attributes;
    type_ = read_type_expr res ld.ld_type; }

let read_type_kind res : Types.type_kind -> type_decl option = function
  | Type_abstract -> None
  | Type_variant cds ->
      Some (Variant (List.map (read_constructor_declaration res) cds))
  | Type_record(lds, _) ->
      Some (Record (List.map (read_label_declaration res) lds))
  | Type_open ->  Some (TYPE_todo "type_open")

let read_type_declaration res id (decl : Types.type_declaration) =
  reset_names ();
  reset_aliased ();
  List.iter add_alias decl.type_params;
  List.iter mark_type decl.type_params;
  iter_opt mark_type decl.type_manifest;
  mark_type_kind decl.type_kind;
  { name = Name.Type.of_string (Ident.name id);
    doc = read_attributes res decl.type_attributes;
    param = List.map (read_type_param res) decl.type_params;
    manifest = map_opt (read_type_expr res) decl.type_manifest;
    decl = read_type_kind res decl.type_kind; }

let rec read_module_declaration res parent id (md : Types.module_declaration) =
  let name = Name.Module.of_string (Ident.name id) in
  let path = Module.create parent name in
  let doc = read_attributes res md.md_attributes in
    match md.md_type with
    | Mty_ident p ->
        let p : module_type_path =
          match find_module_type res p with
          | None -> Unknown (Path.name p)
          | Some p -> Known p
        in
          { path = path; doc; alias = None;
            type_path = Some p; type_ = None }
    | Mty_signature sg ->
        let parent : parent = Module path in
        let sg = read_signature res parent [] sg in
          { path = path; doc; alias = None;
            type_path = None; type_ = Some sg }
    | Mty_functor _ ->
        let sg = MODULE_TYPE_EXPR_todo ("functor:"^Module.to_string path) in
        { path = path; doc; alias = None;
          type_path = None; type_ = Some sg }
    | Mty_alias p ->
        let p : module_path =
          match find_module res p with
          | None -> Unknown (Path.name p)
          | Some p -> Known p
        in
          { path = path; doc; alias = Some p;
            type_path = None; type_ = None }

and read_modtype_declaration res parent id
                             (mtd : Types.modtype_declaration) =
  let name = Name.ModuleType.of_string (Ident.name id) in
  let path = ModuleType.create parent name in
  let doc = read_attributes res mtd.mtd_attributes in
    match mtd.mtd_type with
    | None ->
        { path = path; doc; alias = None; expr = None; }
    | Some (Mty_ident p) ->
        let p : module_type_path =
          match find_module_type res p with
          | None -> Unknown (Path.name p)
          | Some p -> Known p
        in
          { path = path; doc; alias = Some p; expr = None; }
    | Some (Mty_signature sg) ->
        let sg = read_signature res (ModType path) [] sg in
          { path = path; doc; alias = None; expr = Some sg; }
    | Some (Mty_functor _) ->
        let sg = MODULE_TYPE_EXPR_todo ("functor:"^ModuleType.to_string path) in
          { path = path; doc; alias = None; expr = Some sg; }
    | Some (Mty_alias _) -> assert false

and read_signature res parent (acc : signature) = function
  | Sig_value(id, v) :: rest ->
      let v = read_value_description res id v in
      read_signature res parent ((Val v) :: acc) rest
  | Sig_type(id, decl, Trec_first) :: rest ->
      let decl = read_type_declaration res id decl in
      let rec loop acc' = function
        | Sig_type(id, decl, Trec_next) :: rest ->
            let decl = read_type_declaration res id decl in
            loop (decl :: acc') rest
        | rest ->
            read_signature res parent (Types(List.rev acc') :: acc) rest
      in
      loop [decl] rest
  | Sig_type(id, decl, _) :: rest ->
      let decl = read_type_declaration res id decl in
      read_signature res parent ((Types [decl]) ::  acc) rest
  | Sig_typext (id, v, Text_exception) :: rest ->
      let decl = read_extension_constructor res id v in
      read_signature res parent ((Exn decl) :: acc) rest
  | Sig_module(id, md, Trec_first) :: rest ->
      let md = read_module_declaration res parent id md in
      let rec loop acc' = function
        | Sig_module(id, md, Trec_next) :: rest ->
            let md = read_module_declaration res parent id md in
            loop (md :: acc') rest
        | rest ->
            read_signature res parent (Modules(List.rev acc') :: acc) rest
      in
      loop [md] rest
  | Sig_module(id, md, _) :: rest ->
      let md = read_module_declaration res parent id md in
      read_signature res parent ((Modules [md]) :: acc) rest
  | Sig_modtype(id, mtd) :: rest ->
      let mtd = read_modtype_declaration res parent id mtd in
      read_signature res parent ((ModuleType mtd) :: acc) rest
  | x :: rest ->
      read_signature res parent
        (SIG_todo (parent_to_string parent) :: acc) rest
  | [] -> Signature (List.rev acc)

let read_interface res path intf =
  let sg = read_signature res (Module path) [] intf in
    { path = path; doc = {info = []; tags = []; }; alias = None;
      type_path = None; type_ = Some sg }
