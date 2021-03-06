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
open OpamDocTypes

let test cmti =
  let cmti_info = Cmt_format.read_cmt cmti in
  let pkg = OpamPackage.of_string "foo.1" in
  let lib = OpamLibrary.create pkg (OpamLibrary.Name.of_string "bar") in
  let name =
    OpamDocName.Module.of_string cmti_info.Cmt_format.cmt_modname
  in
  let md = Module.create (Lib lib) name in
  let res _ = None in
  let tree =
    match cmti_info.Cmt_format.cmt_annots with
    | Cmt_format.Interface sg -> sg
    | _ -> failwith "Not a cmti file"
  in
  let intf = OpamDocCmti.read_interface_tree res md tree in
  let buf = Buffer.create 1024 in
  let output = Xmlm.make_output (`Buffer buf) in
  OpamDocXml.module_to_xml output intf;
  Buffer.output_buffer stdout buf;
  print_newline ();
  let input = Xmlm.make_input (`String(0, Buffer.contents buf)) in
  let intf2 = OpamDocXml.module_of_xml {OpamDocXml.source = None; input} in
  let buf2 = Buffer.create 1024 in
  let output2 = Xmlm.make_output (`Buffer buf2) in
  OpamDocXml.module_to_xml output2 intf2;
  if buf <> buf2 then begin
    prerr_endline "Error: parsing does not match printing";
    Buffer.output_buffer stderr buf2;
    prerr_newline ();
    1
  end else 0

open Cmdliner

let cmti =
  let doc = "The cmti to test with." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"CMTI" ~doc)

let test =
  let doc = "Test opam-doc-base on cmti files" in
  let info = Term.info ~doc "opam-doc-test-cmti" in
  (Term.(pure test $cmti), info)

let () =
  try
    match Term.eval test with
      `Error _ -> exit 1
    | `Ok code -> exit code
    | `Help | `Version -> exit 0
  with OpamGlobals.Exit i -> exit i
