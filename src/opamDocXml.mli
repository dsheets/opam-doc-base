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

type input = {
  source : string option;
  input  : Xmlm.input;
}

(** Serialize documentation to XML *)

val module_to_xml: Xmlm.output -> OpamDocTypes.module_ -> unit

val module_of_xml: input -> OpamDocTypes.module_

val module_type_to_xml: Xmlm.output -> OpamDocTypes.module_type -> unit

val module_type_of_xml: input -> OpamDocTypes.module_type

val library_to_xml: Xmlm.output -> OpamDocTypes.library -> unit

val library_of_xml: input -> OpamDocTypes.library

val package_to_xml: Xmlm.output -> OpamDocTypes.package -> unit

val package_of_xml: input -> OpamDocTypes.package

