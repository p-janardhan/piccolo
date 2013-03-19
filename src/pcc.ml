
module CBackend = Backend.Make (SeqASTConstC) (SeqASTConstC) (Prims) (SeqASTPrettyPrinterC)

let _ = 
  Printexc.record_backtrace true;
  let ((Syntax.Module m) as mod_def) = ParseUtils.parseFromFile Settings.filename in
  let _ = Middleend.compute_pass mod_def Settings.verbose in
  let main_def, c_code = CBackend.compile_module mod_def in
  let formatter = Format.formatter_of_out_channel (open_out Settings.outname) in
  Printf.printf "%s\n%!" (m#toString);
  let entry_point = m#name ^ "_" ^ "Main"(*main_def#name*) in
  Format.fprintf formatter "%a@\n" 
    CBackend.(print_main Settings.nb_thread entry_point Settings.std_gc_fuel Settings.quick_gc_fuel
		Settings.active_factor main_def#esize main_def#nbChannels main_def#nbChoiceMax) c_code
