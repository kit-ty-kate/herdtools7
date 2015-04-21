(*********************************************************************)
(*                         Diy                                       *)
(*                                                                   *)
(*   Jade Alglave, Luc Maranget INRIA Paris-Rocquencourt, France.    *)
(*                                                                   *)
(*  Copyright 2011 Institut National de Recherche en Informatique et *)
(*  en Automatique. All rights reserved. This file is distributed    *)
(*  under the terms of the Lesser GNU General Public License.        *)
(*********************************************************************)

open Archs
open Printf
open Code

(* Configuration *)
let arch = ref PPC
 
let opts = [Util.arch_opt arch]

module type Config = sig
  val norm : bool
  val compat : bool
  val lowercase : bool
end

module Make (A:Fence.S) =
    struct
      module E = Edge.Make(A)
      module Namer = Namer.Make(A)(E)
      module Normer =
        Normaliser.Make(struct let lowercase = false end)(E)


      let is_ext e = match E.get_ie e with
      | Ext -> true
      | Int -> false

      let atomic = Some A.default_atom

      let atomize es =
        match es with
        | [] -> []
        | fst::_ ->
            let rec do_rec es = match es with
              | [] -> []
              | [e] ->
                  if E.is_ext fst || E.is_ext e then
                    [ { e with E.a2 = atomic ; } ]
                  else
                    es
              | e1::e2::es ->
                  if E.is_ext e1 || E.is_ext e2 then
                    let e1 = { e1 with E.a2 = atomic; } in
                    let e2 = { e2 with E.a1 = atomic; } in
                    e1::do_rec (e2::es)
                  else e1::do_rec (e2::es) in
            match do_rec es with
            | [] -> assert false
            | fst::rem as es ->
                let lst = Misc.last es in
                if is_ext fst || is_ext lst then
                  { fst with E.a1 = atomic;}::rem
                else es
            
      let parse_line s =
        try
          let r = String.index s ':' in
          let name  = String.sub s 0 r
          and es = String.sub s (r+1) (String.length s - (r+1)) in
          let es = E.parse_edges es in
          name,es
        with
        | Not_found | Invalid_argument _ ->
            Warn.fatal "bad line: %s" s

      let pp_edges es = String.concat " " (List.map E.pp_edge es)

      let zyva_stdin () =
        try while true do
          try
            let line = read_line () in
            let _,es = parse_line line in
            let base,es,_ = Normer.normalise_family (atomize es) in
            let name = Namer.mk_name base es in
            printf "%s: %s\n" name (pp_edges es)
          with Misc.Fatal msg -> Warn.warn_always "%s" msg
        done with End_of_file -> ()

      let zyva_argv es =
        let es = List.map E.parse_edge es in
        let es = atomize es in
        printf "%s\n" (pp_edges es)

      let zyva = function
        | [] -> zyva_stdin ()
        | es ->  zyva_argv es
    end

let pp_es = ref []

let () =
  Util.parse_cmdline
    opts
    (fun x -> pp_es := x :: !pp_es)

let pp_es = List.rev !pp_es

let () =
  (match !arch with
  | X86 ->
      let module M = Make(X86Arch) in
      M.zyva
  | PPC ->
      let module M = Make(PPCArch.Make(PPCArch.Config)) in
      M.zyva
  | ARM ->
      let module M = Make(ARMArch) in
      M.zyva
  | AArch64 ->
      let module M = Make(AArch64Arch) in
      M.zyva
  | MIPS ->
      let module M = Make(MIPSArch) in
      M.zyva
  | Bell ->
      let module BellConfig =
        struct
          let debug = !Config.debug
          let verbose = !Config.verbose
          let libdir = Version.libdir
          let prog = Config.prog
          let bell = !Config.bell
          let varatom = !Config.varatom
        end in
      let module M = Make(BellArch.Make(BellConfig)) in
      M.zyva
  | C ->
      let module M = Make(CArch) in
      M.zyva
  | CPP -> Warn.fatal "CCP arch in atomize")      
     pp_es
