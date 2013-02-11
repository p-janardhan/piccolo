
open Types;;
open Syntax;;

open SeqAST;;
open SeqASTConst;;

let make_label, init_label =
  let cpt = ref 0 in
  (fun () -> 
    cpt := succ !cpt; 
    !cpt),
  (fun () -> cpt := 0)

let def_label_pattern m d = (Printf.sprintf "%s_%s_begin" m d)

let d_entry = Val ("0", pint)

let def_fun name = SimpleName name, pdef
let simple_desc name typ = SimpleName name, typ

let make_ite e i1 i2 = Ite (e, i1, i2) (* nicer declaration and indentation *)
let make_it e i = Ite (e, i, [])

let chan = (simple_desc "chan" channel)  (*/!\ en C écrire les foreach dans des blocs *)


let compile_value = function
  | VTrue _ -> Assign (pt_val, Val ("true", pbool))
  | VFalse _ -> Assign (pt_val, Val ("false", pbool))
  | VInt vt -> Assign (pt_val, Val (vt#toString, pint))
  | VString vt -> Assign (pt_val, Val (vt#toString, pstring))
  | VTuple _ -> failwith "TODO compile_value VTuple"
  | VVar vt -> Assign (pt_val, Var (pt_env vt#index) )
  | VPrim _ -> failwith "TODO compile_value VPrim"

and compile_end status =
  Seq [
    Foreach (chan,
	     (CallFun (knows_set_knows, [Var pt_knows])),
	     [CallProc (channel_dec_ref_count, [Var chan]) ]);
    Foreach (chan,
	     (CallFun (knows_set_forget, [Var pt_knows])),
	     [CallProc (channel_dec_ref_count, [Var chan]) ]);
    Assign (pt_status, status);
    return_void]

and compile_wait chans =
  (*  property : chans \inter knows.FORGET = \emptySet  
      [TOASK] -> Maxence, fun intersection de deux ensemble
      C guys -> gestion d'un assert ??
  *)
  Seq [
    Assign (pt_pc, invalid_pc);
    Assign (pt_fuel, fuel_init);
    Foreach (chan,
	     (CallFun (knows_set_forget, [Var pt_knows])),
	     [CallProc (channel_dec_ref_count, [Var chan]);
	      CallProc (knows_set_forget_to_unknown, [Var pt_knows; Var chan])]);
    Assign (pt_status, status_wait);
    CallProc (wait_queue_push, [Var sched_wait; Var pt]);
    CallProc (release, [Var pt_lock]);
    return_void]
and compile_yield label =
  Seq [
    Assign (pt_pc, label);
    Assign (pt_fuel, fuel_init);
    Foreach (chan,
	     (CallFun (knows_set_forget, [Var pt_knows])),
	     [CallProc (channel_dec_ref_count, [Var chan]);
	      CallProc (knows_set_forget_to_unknown, [Var pt_knows; Var chan])]);
    CallProc (ready_queue_add, [Var sched_ready; Var pt]);
    return_void]
    

let eot_label () = Printf.sprintf "end_of_try_%d" (make_label ())

let compile_try_tau = Assign (try_result, try_enabled)
 
let compile_try_in (action:in_action_type) chans = 
  let commit = SimpleName "commit", out_commit in
  let commit_thread = RecordName (commit, "thread"), pi_thread in
  let commit_eval = RecordName(commit, "evalfunc"), eval_ty in
  let ok = SimpleName "ok", commit_status_enum in
  let vl = SimpleName "val", pvalue in
  let pt_env_x = pt_env action#variableIndex in
  let pt_env_c = pt_env action#channelIndex in
  let label_end_of_try = eot_label () in
    Bloc [
      make_it (CallFun (set_add, [Var chans; Var (pt_env_c)]))
	[CallProc (acquire, [Var (pt_env_lock action#channelIndex)])];
      make_it (Op (Equal, Var (RecordName (pt_env_c,"globalrc"), pint), Val ("1", pint)))
	[Assign (try_result, try_disabled);
	 Goto label_end_of_try];
      Declare commit;
      Declare ok;
      
      DoWhile begin [
	Assign (commit, CallFun (fetch_output_commitment, [Var pt_env_c] ));
	
	make_it (Op (Equal, Var commit, Val null))
      	  [Assign (try_result, try_commit);
      	   Goto label_end_of_try];
	
	DoWhile begin 
	  [Assign (ok, CallFun (can_awake, [Var commit_thread; Var commit]));
      	   make_it (Op (Equal, Var ok, commit_cannot_acquire))
      	     [CallProc (low_level_yield,[])]],
      	  (Op (Equal, Var ok, commit_cannot_acquire)) end;
	
	make_it (Op (Equal, Var ok, commit_valid))
      	  [ Declare vl;
	    Assign (vl, CallFun (commit_eval, [Var commit_thread]));
	    Assign (pt_env_x, Var vl);
	    (match action#variableType with
	      | TChan _ -> 
		  make_it (CallFun (knows_register, [Var pt_knows; Var pt_env_x]))
		    [CallProc (channel_incr_ref_count, [Var pt_env_x])]
	      | _ -> Seq []);
	    CallProc (awake, [Var scheduler; Var commit_thread(* ; commit *)]); 
	    (* [TOASK] incohérence au niveau des arguements dans la spec, 
	       vérifier qu'il suffit de scheduler et commit_thread*)
      	    Assign (try_result, try_enabled);
      	    Goto label_end_of_try]],
	
	(CallFun (commit_list_is_empty, 
		  [Var (RecordName (pt_env_c, "outcommits"), commit_list)])) 
      end;
      Label label_end_of_try]
    


let compile_try_out (action:out_action_type) chans = 
  let commit = SimpleName "commit", in_commit in
  let commit_thread = RecordName (commit, "thread"), pi_thread in
  let commit_refvar = RecordName (commit, "refvar"), pint in
  let commit_thread_env_rv = ArrayName (RecordName (commit, "env"), 
					Var commit_refvar), pvalue in
  let ok = SimpleName "ok", commit_status_enum in
  let label_end_of_try = eot_label () in
  let pt_env_c = pt_env action#channelIndex in

  Bloc [
    make_it (CallFun (set_add, [Var chans; Var (pt_env_c)]))
      [CallProc (acquire, [Var (pt_env_lock action#channelIndex)])];
    make_it (Op (Equal, Var (RecordName (pt_env_c,"globalrc"), pint), Val ("1", pint)))
      [Assign (try_result, try_disabled);
       Goto label_end_of_try];
    Declare commit;
    Declare ok;
    DoWhile begin [
      Assign (commit, CallFun (fetch_input_commitment, [Var pt_env_c] ));
      
      make_it (Op (Equal, Var commit, Val null))
      	[Assign (try_result, try_commit);
      	 Goto label_end_of_try];
      
      DoWhile begin 
	[Assign (ok, CallFun (can_awake, [Var commit_thread; Var commit]));
      	 make_it (Op (Equal, Var ok, commit_cannot_acquire))
      	   [CallProc (low_level_yield,[])]],
      	(Op (Equal, Var ok, commit_cannot_acquire)) end;
      
      make_it (Op (Equal, Var ok, commit_valid))
      	[ compile_value action#value;
      	  Assign (commit_thread_env_rv, Var pt_val);
      	  CallProc (awake, [Var scheduler; Var commit_thread(* ; commit *)]);
      	  Assign (try_result, try_enabled);
      	  Goto label_end_of_try]],
      (CallFun (commit_list_is_empty, 
		[Var (RecordName (pt_env_c,"incommits"), commit_list)])) end;
    Label label_end_of_try]

let compile_try_new (action:new_action_type) chans = 
  let newchan = SimpleName "newchan", channel in
  Bloc [
    Declare newchan;
    Assign (newchan, CallFun (generate_channel, []));
    Assign (pt_env action#variableIndex, Var newchan);
    (*[TOASK]!!! dans la spec: knowsSetSwitch(pt.knows,channel,KNOWN*)
    CallProc (knows_register, [Var pt_knows; Var newchan]);
    Assign (try_result, try_enabled)]
    
let compile_try_spawn (action:spawn_action_type) chans = 
  let args i= (ArrayName (SimpleName "args", Val (string_of_int i, pint)), pvalue) in
  let child = SimpleName "child", pi_thread in
    
  let child_proc = (RecordName (child, "proc"), pdef) in
  let child_pc = (RecordName (child, "pc"), pc_label) in
  let child_status =(RecordName (child, "status"), status_enum) in
  let child_knows = (RecordName (child, "knows"), knows_set) in
  let child_env i = (ArrayName ((RecordName (child,"env") ), Val (string_of_int i, pint)), pvalue) in

  let args_mapper i arg =
    Seq [ compile_value arg;
	  Assign (args i, Var pt_val);
	  (match (value_type_of_value arg)#ofType with
	     | TChan _ -> CallProc (knows_register, [Var child_knows; Var (args i)])
	     | _ -> Seq []);
	  Assign ((child_env i), Var (args i));
	]
  in
    Bloc[
      Declare (args action#arity);
      Declare child;
      Assign (child, CallFun (generate_pi_thread, []));
      
      Seq (List.mapi args_mapper action#args);
      
      Assign (child_proc, Val (action#moduleName ^ "_" ^ action#defName, pdef));
      Assign (child_pc, Val ("0", pc_label));
      Assign (child_status, status_run);
      CallProc (ready_queue_push, [Var sched_ready; Var child]);
      Assign (try_result, try_enabled)
    ]

let compile_try_prim (action:prim_action_type) chans = failwith "TODO"

let compile_try_let (action:let_action_type) chans = failwith "TODO"

let compile_try_action (action:action) (chans:varDescr) = 
  (* est il nécessaire de passer chans en arguments ?? *)
  match action with
  | Tau action -> compile_try_tau
  | Output action -> compile_try_out action chans
  | Input action -> compile_try_in action chans
  | New action -> compile_try_new action chans
  | Spawn action -> compile_try_spawn action chans
  | Prim action -> compile_try_prim action chans
  | Let action -> compile_try_let action chans
(* failwith "only a tau, an output or an input action can be tried" *)

let rec compile_process m d proc =
  match proc with
  | Term p -> compile_end status_ended
  | Call p -> compile_call m d p
  | Choice p -> compile_choice m d p

and compile_choice m d p = 
  let nb_disabled = simple_desc "nbdisabled" pint
  and chans = simple_desc "chans" (pset channel)
  and def_label = def_label_pattern m#name d#name
  and choice_cont = Array.make p#arity 0
  in 
  
  for i = 0 to (p#arity - 1) do 
    choice_cont.(i) <- make_label ()
  done;
  
  let guard_mapper = (fun i b ->
    let cont_pc = Val ((string_of_int choice_cont.(i)), pc_label) in
    Seq[
      compile_value b#guard; 
      Assign ((pt_enabled i), Var pt_val); (* ("pt->enabled["^stri^"]=pt->val.content.as_bool;"); *)
      make_ite (Var (pt_enabled i))
	[ make_ite 
	    (Op (Equal, Var try_result, try_disabled))
	    
	    [Assign ((pt_enabled i), Val ("false", pbool));
	     p_inc nb_disabled ]
	    
	    [make_it (Op (Equal, Var try_result, try_enabled))
		[p_dec pt_fuel;
		 make_it (Op (Equal, Var pt_fuel, Val ("0", pint) ))
		   [CallProc (release_all_channels, [Var chans]);
		    compile_yield cont_pc];
		 
		 Assign (pt_pc, cont_pc);
		 Goto def_label]]
	]    
	[p_inc nb_disabled]])
 
  and action_mapper = (fun i b ->
    let pc = Val ((string_of_int choice_cont.(i)), pc_label) in 
    let if_body = 
      match b#action with
      | Output a ->
	let eval = (simple_desc "eval" eval_ty) in
	[DeclareFun (eval, ["pt"] ,[compile_value a#value; Return (Var pt_val)]);
	 CallProc (register_output_commitment, 
		   [Var pt; Var (pt_env a#channelIndex); Var eval; pc])]
	  
      | Input a -> 
	[CallProc (register_input_commitment, 
		   [Var pt; Var (pt_env a#channelIndex);
		    Val (string_of_int a#variableIndex, pint); pc])]
      | _ -> []
    in
    make_it (Var (pt_enabled i)) if_body
  )
  in
  Bloc (* cvar after_wait_fuel : label *)
    [Declare try_result ;
     Declare nb_disabled ;
     Assign (nb_disabled, Val ("0", pint));
     Declare chans;
     
     Seq (List.mapi guard_mapper p#branches);
     
     make_it ( Op (Equal, Var nb_disabled, Val (string_of_int p#arity, pint) ))
       [ CallProc (release_all_channels, [Var chans]);
	 compile_end status_blocked ];
     
     Seq (List.mapi action_mapper p#branches);
     
     CallProc (acquire, [Var pt_lock]);
     CallProc (release_all_channels, [Var chans]);
     compile_wait chans; (* /!\ unused parameter !! -> assert  cf compile_wait *)
     
     Seq (List.mapi (fun i prefix -> 
       Seq [ Case (Val (string_of_int choice_cont.(i), pint));
	     compile_process m d prefix#continuation]
     ) p#branches)]

(* dans un switch case, le case peut être imbriqué dans plusieurs bloc !!

    on aura:
       def(){ 
       
       label @def:

       switch ()
       case def_id :

          { Choice X 
       
            pt.pc <- cont_X
            GOTO @def;
 
            case cont_X:

            case cont_Y:
       
          }
      
       }
    *)
and compile_call m d p =
  
  let args i= (ArrayName (SimpleName "args", Val (string_of_int i, pint)), pvalue) in
  
  let rec init_env acc i argsTypes =
    match argsTypes with
    | [] -> acc
    | arg::tl -> 
      let assign = Assign ((pt_env i), Var (args i)) in
      let acc' = acc@
	[ match arg with
	| TChan _ -> Seq [ assign; CallProc (knows_register, [Var pt_knows; Var (args i)]) ]
	| _ -> assign ]
      in
      init_env acc' (i+1) tl
  in	      
  
  Bloc [
    Declare (args p#arity);
    CallProc (knows_set_forget_all, [ Var pt_knows ]);

    Seq (List.mapi 
	   (fun i v -> Seq [ compile_value v; Assign ((args i), Var pt_val)])
	   p#args);
    
    Seq (init_env [] 0 p#argTypes);
    
    Assign (pt_proc , Var (def_fun (m#name ^ "_" ^ d#name)));
    Assign (pt_pc, d_entry);
    Assign (pt_status, status_call);
    return_void]
       
let compile_def m (Def d) =
  init_label ();
  DeclareFun (def_fun (m#name ^ "_" ^ d#name), ["scheduler"; "pt"],
	      [Label (def_label_pattern m#name d#name);
		Switch (Var pt_pc, [Case d_entry;
			       compile_process m d d#process
			      ])])

let compile_module (Module m) =
  Seq (List.map (compile_def m) m#definitions)



