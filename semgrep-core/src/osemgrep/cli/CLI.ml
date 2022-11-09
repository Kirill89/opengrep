(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
   Library defining the semgrep command-line interface.

   This module determines the subcommand invoked on the command line
   and has another module handle it as if it were an independent command.
   We don't use Cmdliner to dispatch subcommands because it's too
   complicated and we never show a help page for the whole command anyway
   since we fall back to the 'scan' subcommand if none is given.

   Translated from cli.py
*)

(*****************************************************************************)
(* TOPORT *)
(*****************************************************************************)

(* TOPORT:
      def maybe_set_git_safe_directories() -> None:
          """
          Configure Git to be willing to run in any directory when we're in Docker.

          In docker, every path is trusted:
          - the user explicitly mounts their trusted code directory
          - r2c provides every other path

          More info:
          - https://github.blog/2022-04-12-git-security-vulnerability-announced/
          - https://github.com/actions/checkout/issues/766
          """
          env = get_state().env
          if not env.in_docker:
              return

          try:
              # "*" is used over Path.cwd() in case the user targets an absolute path instead of setting --workdir
              git_check_output(["git", "config", "--global", "--add", "safe.directory", "*"])
          except Exception as e:
              logger.info(
                  f"Semgrep failed to set the safe.directory Git config option. Git commands might fail: {e}"
              )

   def abort_if_linux_arm64() -> None:
       """
       Exit with FATAL_EXIT_CODE if the user is running on Linux ARM64.
       Print helpful error message.
       """
       if platform.machine() in {"arm64", "aarch64"} and platform.system() == "Linux":
           logger.error("Semgrep does not support Linux ARM64")
           sys.exit(FATAL_EXIT_CODE)
*)

(*****************************************************************************)
(* Subcommands dispatch *)
(*****************************************************************************)

(* This is used to determine if we should fall back to assuming 'scan'. *)
let known_subcommands =
  [ "ci"; "login"; "logout"; "lsp"; "publish"; "scan"; "shouldafound" ]

(* Exit with a code that a proper semgrep implementation would never return.
   Uncaught OCaml exception result in exit code 2.
   This is to ensure that the tests that expect error status 2 fail. *)
let missing_subcommand () =
  Printf.eprintf "This semgrep subcommand is not implemented\n%!";
  Exit_code.not_implemented_in_osemgrep

(* python: the help message was automatically generated by Click
 * based on the docstring and the subcommands. In OCaml we have to
 * generate it manually unfortunately.
 *)
let main_help_msg =
  {|Usage: semgrep [OPTIONS] COMMAND [ARGS]...

  To get started quickly, run `semgrep scan --config auto`

  Run `semgrep SUBCOMMAND --help` for more information on each subcommand

  If no subcommand is passed, will run `scan` subcommand by default

Options:
  -h, --help  Show this message and exit.

Commands:
  ci            The recommended way to run semgrep in CI
  login         Obtain and save credentials for semgrep.dev
  logout        Remove locally stored credentials to semgrep.dev
  lsp           [EXPERIMENTAL] Start the Semgrep LSP server
  publish       Upload rule to semgrep.dev
  scan          Run semgrep rules on files
  shouldafound  Report a false negative in this project.
|}

let default_subcommand = "scan"

let dispatch_subcommand argv =
  match Array.to_list argv with
  (* impossible because argv[0] contains the program name *)
  | [] -> assert false
  | [ _; ("-h" | "--help") ] ->
      print_string main_help_msg;
      Exit_code.ok
  | argv0 :: args -> (
      let subcmd, subcmd_args =
        match args with
        | [] -> (default_subcommand, [])
        | arg1 :: other_args ->
            if List.mem arg1 known_subcommands then (arg1, other_args)
            else
              (* No valid subcommand was found.
                 Assume the 'scan' subcommand was omitted and insert it. *)
              (default_subcommand, arg1 :: other_args)
      in
      let subcmd_argv =
        let subcmd_argv0 = argv0 ^ "-" ^ subcmd in
        subcmd_argv0 :: subcmd_args |> Array.of_list
      in
      (* coupling: with known_subcommands if you add an entry below.
       * coupling: with the main_help_msg if you add an entry below.
       *)
      match subcmd with
      | "ci" -> Ci_subcommand.main subcmd_argv
      | "login" -> Login_subcommand.main subcmd_argv
      | "logout" -> Logout_subcommand.main subcmd_argv
      | "lsp" -> missing_subcommand ()
      | "publish" -> missing_subcommand ()
      | "scan" -> Scan_subcommand.main subcmd_argv
      | "shouldafound" -> missing_subcommand ()
      (* TOPORT: cli.add_command(install_deep_semgrep) *)
      | _else_ -> (* should have defaulted to 'scan' above *) assert false)

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let main argv =
  Printexc.record_backtrace true;

  (* LATER: move this function from Core_CLI to here at some point *)
  Core_CLI.register_exception_printers ();

  (* Some copy-pasted code from Core_CLI.ml *)
  (* SIGXFSZ (file size limit exceeded)
   * ----------------------------------
   * By default this signal will kill the process, which is not good. If we
   * would raise an exception from within the handler, the exception could
   * appear anywhere, which is not good either if you want to recover from it
   * gracefully. So, we ignore it, and that causes the syscalls to fail and
   * we get a `Sys_error` or some other exception. Apparently this is standard
   * behavior under both Linux and MacOS:
   *
   * > The SIGXFSZ signal is sent to the process. If the process is holding or
   * > ignoring SIGXFSZ, continued attempts to increase the size of a file
   * > beyond the limit will fail with errno set to EFBIG.
   *)
  Sys.set_signal Sys.sigxfsz Sys.Signal_ignore;

  (* TODO? the logging setup is now done in Semgrep_scan.ml, because that's
   * when we have a config object, but ideally we would like
   * to analyze argv and do it sooner for all subcommands here.
   * update: now that we use the Logs library, maybe we could do it
   * here as we don't need a config object anymore.
   *)

  (* TOADAPT
     profile_start := Unix.gettimeofday ();

     if config.lsp then LSP_client.init ();

     (* must be done after Arg.parse, because Common.profile is set by it *)
     Common.profile_code "Main total" (fun () ->
             (* TODO: We used to tune the garbage collector but from profiling
                we found that the effect was small. Meanwhile, the memory
                consumption causes some machines to freeze. We may want to
                tune these parameters in the future/do more testing, but
                for now just turn it off *)
             (* if !Flag.gc_tuning && config.max_memory_mb = 0 then set_gc (); *)
             let config = { config with roots } in
             Run_semgrep.semgrep_dispatch config)
  *)
  (* TOPORT:
      state = get_state()
      state.terminal.init_for_cli()
      abort_if_linux_arm64()
      commands: Dict[str, click.Command] = ctx.command.commands
      subcommand: str = (
          ctx.invoked_subcommand if ctx.invoked_subcommand in commands else "unset"
      )
      state.app_session.authenticate()
      state.app_session.user_agent.tags.add(f"command/{subcommand}")
      state.metrics.add_feature("subcommand", subcommand)
      maybe_set_git_safe_directories()
  *)
  dispatch_subcommand argv

(* TOADAPT:
   let main (argv : string array) : unit =
     Common.main_boilerplate (fun () ->
         Common.finalize
           (fun () -> main argv)
           (fun () -> !Hooks.exit |> List.iter (fun f -> f ())))
*)
