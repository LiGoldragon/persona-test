# message-flow — the Flow 0.17.4 live-start witness, a semi-sandbox runner.
#
#   nix run .#message-flow                  the stand-in mode (the default)
#   nix run .#message-flow -- stand-in      the same, named
#   nix run .#message-flow -- live-claude   refuses: awaits the living's ruling
#   PERSONA_TEST_CODEX_CLIENT=... PERSONA_TEST_CODEX_HOME=... \
#   PERSONA_TEST_CODEX_CONTROL_SOCKET=... nix run .#message-flow -- live-codex
#
# Two modes, kept apart.
#
#   stand-in   every seat is the stand-in program of
#              lib/components/claude-stand-in.nix, which is NOT Claude. No
#              login, no credential and no configuration directory of the
#              user is read, and no seat login is projected: the login
#              route awaits the living's ruling. It is what the default run
#              and the check `message-flow-stand-in` (in the build sandbox,
#              no network) do.
#              It checks the scenario's own logic and witnesses nothing about
#              any harness.
#   live       reached only by hand, never from a check or the default run,
#              and refused unless its parameters are given from outside:
#     live-claude  REFUSES, before it makes a root or starts anything. How a
#              test seat gets a Claude login (a copy of the credential, or a
#              share of the live configuration) awaits the living's ruling;
#              the ruled route is to be written in this form's branch below.
#              When it is, starts A, B, C and case D run the real Claude
#              harness; E, F and J stay on the stand-in, since each needs a
#              seat that misbehaves in one known way. Only this form, once
#              written, witnesses anything about the Claude harness.
#     live-codex   one Codex start, List, Stop, List on an already isolated
#              Codex endpoint the caller names in PERSONA_TEST_CODEX_CLIENT,
#              PERSONA_TEST_CODEX_HOME and PERSONA_TEST_CODEX_CONTROL_SOCKET;
#              the runner reads and copies no Codex credential. No transcript
#              oracle is written for Codex yet: this form asserts Flow's
#              answers and that the pane is gone after the stop. It does not
#              observe the Codex seat's process.
#
# What a run does, all under one fresh root removed at exit:
#   its own Flow 0.17.4 (client and service from one build), its own
#   Message, its own headless Herdr server with one named session and its
#   own configuration home; then, one at a time, starts A (two short lines),
#   B (one line over 800 UTF-16 units), C (one short line), and the cases
#   that must fail: D (a skill that cannot load), E (another model), F (the
#   first entry is not the stored prompt), J (footer kept, body altered).
#   Seven of the eleven planned cases. G, H, I and K are not written; the
#   report says so and what each would have covered.
#   After each: list, a typed stop, list again, the seat's pane and process
#   shown gone. For each, fixtures/message-flow/oracle.py reads the seat's
#   own transcript from disk and judges it without asking Flow; Flow's
#   verdict and the oracle's must agree. The report is written under the
#   root and printed before the root is removed.
{
  pkgs,
  flake,
  system,
  ...
}:
let
  inherit (flake.lib) components;
  flow = components.flow.forSystem system;
  message = components.message.forSystem system;
  herdr = components.herdr.forSystem system;
  flowId = components.flow-id.forSystem system;
  seat = components.claude-stand-in.forSystem system;
  fixtures = ../fixtures/message-flow;
  oracle = "${pkgs.python3}/bin/python3 ${fixtures}/oracle.py";

  # A pane shell that reads no rc or profile file: the host's /etc/bashrc
  # would put the host's PATH, and the host's `claude`, back in front.
  seatShell = pkgs.writeShellScript "seat-shell" ''
    exec ${pkgs.bashInteractive}/bin/bash --norc --noprofile "$@"
  '';

  # The pane's PATH. The seat dispatcher's `claude` comes first.
  seatPath = pkgs.lib.makeBinPath [
    seat.dispatcher
    pkgs.python3
    pkgs.coreutils
    pkgs.bashInteractive
    pkgs.gnugrep
    pkgs.gnused
    pkgs.git
    herdr.package
  ];

  # The runner's own PATH once its environment is emptied.
  runnerPath = pkgs.lib.makeBinPath [
    pkgs.coreutils
    pkgs.jq
    pkgs.procps
    pkgs.gnugrep
  ];

  # Flow's PATH: the Herdr CLI and the flow-id claim helper, nothing else.
  flowPath = pkgs.lib.makeBinPath [
    herdr.package
    flowId.package
    pkgs.coreutils
  ];
in
pkgs.writeShellApplication {
  name = "message-flow";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
    pkgs.procps
    pkgs.gnugrep
  ];

  meta.description = "Flow 0.17.4 live-start witness: its own Flow, Message and Herdr under one root; starts A, B, C and must-fail cases D, E, F, J judged against the seat's own transcript.";

  text = ''
    # The runner's own shell starts from an emptied environment, so that no
    # call site has to guard against what the caller exported. It re-executes
    # itself under `env -i` with only its PATH, LANG, the PERSONA_TEST_*
    # parameters the caller gave, and the caller's HOME and runtime directory
    # under names of their own, kept only to refuse them as live paths below.
    if [ "''${PERSONA_TEST_RUNNER_EMPTIED:-}" != 1 ]; then
      carried=()
      for carriedName in PERSONA_TEST_ROOT_BASE PERSONA_TEST_MODEL PERSONA_TEST_CODEX_CLIENT PERSONA_TEST_CODEX_HOME PERSONA_TEST_CODEX_CONTROL_SOCKET; do
        if [ -n "''${!carriedName:-}" ]; then
          carried+=("$carriedName=''${!carriedName}")
        fi
      done
      exec env -i \
        PERSONA_TEST_RUNNER_EMPTIED=1 \
        PERSONA_TEST_CALLER_HOME="''${HOME:-}" \
        PERSONA_TEST_CALLER_RUNTIME="''${XDG_RUNTIME_DIR:-}" \
        PATH="${runnerPath}" \
        LANG=C.UTF-8 \
        "''${carried[@]}" \
        "$0" "$@"
    fi
    for exportedName in $(compgen -e); do
      case "$exportedName" in
        PATH | LANG | PWD | OLDPWD | SHLVL | _ | PERSONA_TEST_RUNNER_EMPTIED | PERSONA_TEST_CALLER_HOME | PERSONA_TEST_CALLER_RUNTIME) ;;
        PERSONA_TEST_ROOT_BASE | PERSONA_TEST_MODEL | PERSONA_TEST_CODEX_CLIENT | PERSONA_TEST_CODEX_HOME | PERSONA_TEST_CODEX_CONTROL_SOCKET) ;;
        *)
          echo "refusing: the runner's environment was not emptied; $exportedName survived" >&2
          exit 70
          ;;
      esac
    done
    callerHome="''${PERSONA_TEST_CALLER_HOME:-}"
    callerRuntime="''${PERSONA_TEST_CALLER_RUNTIME:-}"
    unset PERSONA_TEST_CALLER_HOME PERSONA_TEST_CALLER_RUNTIME PERSONA_TEST_RUNNER_EMPTIED

    ${flake.lib.shellHelpers}

    mode="''${1:-stand-in}"
    codexClient=""
    flowDeploymentOverrides=()
    case "$mode" in
      stand-in) ;;
      live-claude)
        # The ruled login route for a test seat is to be written here. Until
        # the living rules, this form makes no root and starts nothing.
        echo "refusing: live-claude awaits the living's ruling on the login route for test seats (a copy of the credential, or a share of the live configuration); no root was made and nothing was started" >&2
        exit 69
        ;;
      live-codex)
        codexClient="''${PERSONA_TEST_CODEX_CLIENT:-}"
        codexHome="''${PERSONA_TEST_CODEX_HOME:-}"
        codexControlSocket="''${PERSONA_TEST_CODEX_CONTROL_SOCKET:-}"
        requireAbsolute PERSONA_TEST_CODEX_CLIENT "$codexClient"
        requireAbsolute PERSONA_TEST_CODEX_HOME "$codexHome"
        requireAbsolute PERSONA_TEST_CODEX_CONTROL_SOCKET "$codexControlSocket"
        codexModel="''${PERSONA_TEST_MODEL:-${flake.lib.cheapestModel.codex}}"
        for endpoint in STABLE NEXT; do
          flowDeploymentOverrides+=(
            "FLOW_CODEX_''${endpoint}_CLIENT=$codexClient"
            "FLOW_CODEX_''${endpoint}_HOME=$codexHome"
            "FLOW_CODEX_''${endpoint}_SOCKET=$codexControlSocket"
            "FLOW_CODEX_''${endpoint}_MODELS=$codexModel"
          )
        done
        ;;
      *)
        echo "usage: message-flow [stand-in] | live-claude (refuses until ruled) | live-codex" >&2
        echo "Only a live form witnesses anything about a harness; the stand-in is not Claude." >&2
        exit 64
        ;;
    esac

    model="${flake.lib.cheapestModel.claude}"
    effort=medium
    skills=(spirit testing operational-final-response)
    flowRevision="${flow.revision}"

    ${flake.lib.isolatedStateRoot}

    runId="$(basename "$stateRoot")"
    reportDirectory="$stateRoot/report"
    report="$reportDirectory/report.txt"
    mkdir -p "$reportDirectory"
    say() { printf '%s\n' "$*" >>"$report"; }

    flowHome="$stateRoot/flow/home"
    flowRuntime="$stateRoot/flow/run"
    flowLog="$reportDirectory/flow-nexus.log"
    messageHome="$stateRoot/message/home"
    messageRuntime="$stateRoot/message/run"
    messageLog="$reportDirectory/message-nexus.log"
    herdrConfigHome="$stateRoot/herdr/config"
    herdrStateHome="$stateRoot/herdr/state"
    herdrRuntime="$stateRoot/herdr/run"
    herdrLog="$reportDirectory/herdr-server.log"
    herdrSession=persona-test
    seatChoiceFile="$stateRoot/seat/choice"
    seatShell="${seatShell}"
    seatPath="${seatPath}"
    flowPath="${flowPath}"

    seatHome="$stateRoot/seat/home"
    seatDir="$stateRoot/seat/work"
    seatClaudeConfigDir="$seatHome/.claude"

    # No derived path may be, or lie under, a live one of the caller's: the
    # runtime directory /run/user/<uid> and the caller's own, Flow's live
    # state under the caller's HOME, Herdr's live configuration home. Each
    # must be absolute and under this run's root. Checked before anything
    # starts; a refusal removes the root.
    livePaths=("/run/user/$(id -u)")
    if [ -n "$callerRuntime" ]; then
      livePaths+=("''${callerRuntime%/}")
    fi
    if [ -n "$callerHome" ]; then
      livePaths+=("''${callerHome%/}/.local/state/flow" "''${callerHome%/}/.config/herdr")
    fi
    refuseLive() {
      for livePath in "''${livePaths[@]}"; do
        case "$2/" in
          "$livePath"/*)
            echo "refusing: $1 is or lies under the live path $livePath: $2" >&2
            exit 70
            ;;
        esac
      done
    }
    refuseLive "the run's root" "$stateRoot"
    for derivedName in flowHome flowRuntime messageHome messageRuntime herdrConfigHome herdrStateHome herdrRuntime seatHome seatDir seatClaudeConfigDir; do
      derivedPath="''${!derivedName}"
      requireAbsolute "$derivedName" "$derivedPath"
      case "$derivedPath/" in
        "$stateRoot"/*) ;;
        *)
          echo "refusing: $derivedName is not under this run's root: $derivedPath" >&2
          exit 70
          ;;
      esac
      refuseLive "$derivedName" "$derivedPath"
    done

    for socket in \
      "$flowRuntime/${flow.ordinarySocket}" "$flowRuntime/${flow.metaSocket}" \
      "$messageRuntime/${message.ordinarySocket}" "$messageRuntime/${message.metaSocket}" \
      "$herdrConfigHome/herdr/sessions/$herdrSession/herdr.sock" \
      "$herdrConfigHome/herdr/sessions/$herdrSession/herdr-client.sock"; do
      requireSocketLength "$socket"
    done

    # The seat's identity: plain directories under the root. No login is
    # projected, no credential is read, and no file holding a secret is made.
    mkdir -p "$seatClaudeConfigDir/projects" "$seatDir/flows" "$seatDir/.claude/skills"
    for skill in "''${skills[@]}"; do
      cp -r "${fixtures}/skills/$skill" "$seatDir/.claude/skills/$skill"
    done
    chmod -R u+w "$seatDir/.claude"
    bundle="$seatDir/flow-system-prompt.md"
    cp "${fixtures}/flow-system-prompt.md" "$bundle"
    chmod u+w "$bundle"

    flowSourceRoot="$seatDir"
    flowClaudeConfigDir="$seatClaudeConfigDir"

    ${herdr.call}
    ${flow.call}

    # Every process the runner starts is held by its PID. A Flow client call
    # that may run long is started in the background and waited for, so a
    # signal reaches the trap at once and the trap stops it by that PID.
    heldPid=""
    observerPid=""
    held() {
      local out="$1"
      shift
      "$@" >>"$out" 2>&1 &
      heldPid=$!
      wait "$heldPid" || true
      heldPid=""
    }
    stopObserver() {
      if [ -n "$observerPid" ]; then
        pkill -P "$observerPid" 2>/dev/null || true
        kill "$observerPid" 2>/dev/null || true
        wait "$observerPid" 2>/dev/null || true
        observerPid=""
      fi
    }

    beforeRootRemoval() {
      if [ -n "$heldPid" ]; then
        kill "$heldPid" 2>/dev/null
        wait "$heldPid" 2>/dev/null
        heldPid=""
      fi
      stopObserver
      ${flow.stop}
      ${message.stop}
      ${herdr.stop}
      if [ -f "$report" ]; then
        cat "$report"
      fi
    }

    ${herdr.config}
    ${herdr.start}
    ${flow.start}
    ${message.start}

    say "message-flow — Flow 0.17.4 live-start witness"
    say "mode: $mode"
    say "flow revision: $flowRevision (client ${flow.client})"
    say "herdr revision: ${herdr.revision}, session $herdrSession under $herdrConfigHome"
    say "harness (flow-id) revision: ${flowId.revision}"
    say "message revision: ${message.revision} (started, not driven)"
    say "root: $stateRoot (removed at exit)"
    if [ "$mode" = stand-in ]; then
      say "worth: every seat of this run is the stand-in, which is not Claude."
      say "  This run proves the scenario's own logic and nothing about a real harness."
    else
      say "worth: the Codex seat is the endpoint the caller gave; no transcript oracle judges it,"
      say "  and its process is not observed. Only Flow's answers and the pane are checked."
    fi
    say ""

    # --- one start -------------------------------------------------------
    promotionWait() {
      if [ "$1" = started ] && [ "$mode" != stand-in ]; then echo 300; else echo 30; fi
    }

    observeLaunch() {
      for _ in $(seq 1 600); do
        timeout 900 env -i FLOW_SOCKET="$flowRuntime/${flow.ordinarySocket}" ${flow.client} "Observe.Launch.$1" >>"$2" 2>&1 || true
        if grep -q 'LaunchPending\|^Started\|^StartRejected' "$2"; then
          return 0
        fi
        sleep 0.05
      done
    }

    seatProcesses() {
      ${oracle} processes "$herdrServerPid" |
        jq -c '[.[] | select(any(.argv[]; (split("/") | last) == "claude"))]'
    }

    # runCase NAME SEAT-CHOICE EXPECT FORM WRAPPED SKILL... -- INSTRUCTION
    # EXPECT is `started`, `unloaded-skill`, or the oracle check that must
    # be the first to fail.
    failures=0
    runCase() {
      local name="$1" choice="$2" expect="$3" form="$4" wrapped="$5"
      shift 5
      local caseSkills=()
      while [ "$1" != -- ]; do caseSkills+=("$1"); shift; done
      shift
      local instruction="$1"
      local caseDirectory="$reportDirectory/case-$name"
      local launchId="mf-$name-$runId"
      mkdir -p "$caseDirectory"
      printf '%s\n' "$choice" >"$seatChoiceFile"

      local escaped="''${instruction//\\/\\\\}"
      escaped="''${escaped//»/\\»}"
      local datom="Start.{ { $launchId [] [ ''${caseSkills[*]} ] Field UltraLow Claude $model $effort None [] $herdrSession «$bundle» «$escaped» } { pt0000 message-flow-$runId case-$name } }"

      say "case $name — seat $choice — expect $expect"
      say "  command: flow '$datom'"
      say "  revision: $flowRevision"

      observeLaunch "$launchId" "$caseDirectory/observe.txt" &
      observerPid=$!
      held "$caseDirectory/start.reply" timeout 900 env -i FLOW_SOCKET="$flowRuntime/${flow.ordinarySocket}" ${flow.client} "$datom"
      say "  start answered: $(head -c 300 "$caseDirectory/start.reply" | tr '\n' ' ')"
      stopObserver

      if grep -q '^StartAmbiguous' "$caseDirectory/start.reply"; then
        held "$caseDirectory/observe.txt" timeout "$(promotionWait "$expect")" env -i FLOW_SOCKET="$flowRuntime/${flow.ordinarySocket}" ${flow.client} "Observe.Launch.$launchId"
      fi
      flowCall "LaunchStatus.$launchId" >"$caseDirectory/final.reply" 2>&1 || true

      local facts verdict flowIdentity session pane stored phases
      facts="$(${oracle} reply "$caseDirectory/observe.txt" "$caseDirectory/start.reply" "$caseDirectory/final.reply")"
      phases="$(jq -r '(.phases // []) | join(" ")' <<<"$facts")"
      verdict="$(jq -r '.verdict // "none"' <<<"$facts")"
      flowIdentity="$(jq -r '.flow_id // ""' <<<"$facts")"
      session="$(jq -r '.session_id // ""' <<<"$facts")"
      pane="$(jq -r '.pane_id // ""' <<<"$facts")"
      stored="$(jq -r '.prompt_sha256 // ""' <<<"$facts")"
      say "  flow verdict: $verdict; flow $flowIdentity; native session $session; pane $pane"
      say "  stored prompt hash (from Flow): $stored"
      say "  launch phases Flow reported: ''${phases:-none}"

      local processes
      processes="$(seatProcesses)"
      say "  seat processes: $(jq -c '[.[] | {pid, argv: (.argv | map(split("/") | last) | .[0:12])}]' <<<"$processes")"

      local unavailable=""
      for skill in "''${caseSkills[@]}"; do
        case " ''${skills[*]} " in
          *" $skill "*) ;;
          *) unavailable="$skill" ;;
        esac
      done

      local judged='{"checks":[],"passed":false,"first_failed":"no-native-session"}'
      if [ -n "$session" ]; then
        local skillPaths=()
        for skill in "''${caseSkills[@]}"; do
          skillPaths+=("$seatDir/.claude/skills/$skill/SKILL.md")
        done
        jq -n \
          --arg session_id "$session" \
          --arg projects "$seatClaudeConfigDir/projects" \
          --arg instruction "$instruction" \
          --arg stored_sha256 "$stored" \
          --arg model "$model" \
          --arg effort "$effort" \
          --arg form "$form" \
          --argjson wrapped "$wrapped" \
          --arg bundle_directory "$flowHome/.local/state/flow/launch-bundles" \
          --argjson seat_argv "$(jq -c '(.[-1].argv // [])' <<<"$processes")" \
          --arg seat "''${choice%% *}" \
          --arg unavailable_skill "$unavailable" \
          --arg claude_catalog "$seatClaudeConfigDir/skills" \
          --arg project_catalog "$seatDir/.claude/skills" \
          '{session_id: $session_id, projects: $projects, instruction: $instruction,
            stored_sha256: $stored_sha256, model: $model, effort: $effort, form: $form,
            wrapped: $wrapped, bundle_directory: $bundle_directory, seat_argv: $seat_argv,
            seat: $seat, unavailable_skill: $unavailable_skill,
            catalogs: [$claude_catalog, $project_catalog],
            skills: $ARGS.positional[0:($ARGS.positional | length / 2)],
            skill_paths: $ARGS.positional[($ARGS.positional | length / 2):]}' \
          --args "''${caseSkills[@]}" "''${skillPaths[@]}" >"$caseDirectory/oracle-spec.json"
        judged="$(${oracle} transcript "$caseDirectory/oracle-spec.json")"
      fi
      jq -r '.checks[] | "    \(if .passed then "pass" else "FAIL" end) \(.name): \(.detail)"' <<<"$judged" >>"$report"
      local passed firstFailed
      passed="$(jq -r .passed <<<"$judged")"
      firstFailed="$(jq -r '.first_failed // "none"' <<<"$judged")"

      local outcome
      case "$expect" in
        started)
          if [ "$verdict" = Started ] && [ "$passed" = true ]; then
            outcome="ok: Flow started the seat and the transcript agrees"
          elif [ "$verdict" = Started ]; then
            outcome="DISAGREE: Flow said Started, the transcript failed $firstFailed"
          elif [ "$passed" = true ]; then
            outcome="DISAGREE: Flow said $verdict, the transcript passed every check"
          else
            outcome="FAILED: Flow said $verdict and the transcript failed $firstFailed"
          fi
          ;;
        unloaded-skill)
          # Pinned: Flow refuses registration after acknowledging it, the
          # seat's own transcript exists and holds no first prompt, and the
          # oracle found the skill in no catalog Flow reads (its check runs
          # before first-entry-present). Any other answer or first failure
          # fails the case. Flow names RegistrationRefused both when a skill
          # cannot be resolved and when the prompt intent is not accepted;
          # its answer alone cannot tell those apart, and the report says so.
          if [ "$verdict" = StartRejected.RegistrationRefused ] &&
            [ "$firstFailed" = first-entry-present ] &&
            [[ " $phases " == *" RegistrationAcknowledged "* ]]; then
            outcome="ok: Flow refused registration after acknowledging it, the seat never got its first prompt, and $unavailable is in no catalog Flow reads"
          else
            outcome="FAILED: case D wants StartRejected.RegistrationRefused after RegistrationAcknowledged, with the transcript present and no first entry; Flow said $verdict (phases: ''${phases:-none}), transcript first failed at $firstFailed"
          fi
          say "  note: Flow's answer does not by itself name which skill failed or tell skill resolution from intent acceptance; the reason is the catalog check above."
          ;;
        *)
          if [ "$verdict" != Started ] && [ "$firstFailed" = "$expect" ]; then
            outcome="ok: Flow did not accept the start ($verdict) and the transcript shows $expect stopped it"
          elif [ "$verdict" = Started ]; then
            outcome="DISAGREE: Flow said Started, the transcript first failed $firstFailed"
          else
            outcome="FAILED: Flow said $verdict, but the transcript first failed $firstFailed, not $expect"
          fi
          ;;
      esac

      # List, a typed stop, list again, the pane and the process gone.
      local stopOk=true
      if [ -n "$flowIdentity" ]; then
        flowCall 'List.{ }' >"$caseDirectory/list-before.reply" 2>&1 || true
        say "  list before stop: $flowIdentity is $(${oracle} lifecycle "$caseDirectory/list-before.reply" "$flowIdentity")"
        flowCall "Stop.$flowIdentity" >"$caseDirectory/stop.reply" 2>&1 || true
        say "  stop: $(tr '\n' ' ' <"$caseDirectory/stop.reply")"
        flowCall 'List.{ }' >"$caseDirectory/list-after.reply" 2>&1 || true
        local after
        after="$(${oracle} lifecycle "$caseDirectory/list-after.reply" "$flowIdentity")"
        say "  list after stop: $flowIdentity is $after"
        [ "$after" = Stopped ] || stopOk=false
      else
        say "  no flow was registered; nothing to stop"
      fi
      if [ -n "$pane" ]; then
        if herdrCall pane get "$pane" >"$caseDirectory/pane-after.json" 2>&1; then
          say "  pane $pane: STILL PRESENT"
          stopOk=false
          herdrCall pane close "$pane" >/dev/null 2>&1 || true
        else
          say "  pane $pane: gone"
        fi
      fi
      local pids=()
      mapfile -t pids < <(jq -r '.[].pid' <<<"$processes")
      if [ "''${#pids[@]}" -gt 0 ]; then
        for _ in $(seq 1 100); do
          [ "$(${oracle} alive "''${pids[@]}")" = "[]" ] && break
          sleep 0.1
        done
        local alive
        alive="$(${oracle} alive "''${pids[@]}")"
        if [ "$alive" = "[]" ]; then
          say "  seat processes ''${pids[*]}: gone"
        else
          say "  seat processes still alive: $alive"
          stopOk=false
        fi
      elif [ "$expect" != unloaded-skill ] || [ -n "$pane" ]; then
        say "  no seat process was seen under this run's Herdr"
      fi
      if [ "$stopOk" != true ]; then
        outcome="$outcome; STOP INCOMPLETE"
      fi
      case "$outcome" in
        ok:*) ;;
        *) failures=$((failures + 1)) ;;
      esac
      say "  result: $outcome"
      say ""
    }

    # --- live-codex: one Codex start on an endpoint given from outside -----
    # Carried from main c1a2370's runner: a launch source brief.md checked by
    # its exact hash, Start, List, Stop, List. Its endpoint reaches Flow as
    # FLOW_CODEX_* deployment overrides at start, not by a meta Configure
    # and a restart.
    runLiveCodex() {
      local caseDirectory="$reportDirectory/case-codex"
      local launchId="mf-codex-$runId"
      mkdir -p "$caseDirectory"
      printf '%s\n' 'Start, List, and Stop are the bounded message-flow scenario.' >"$seatDir/brief.md"
      local briefHash
      briefHash="$(sha256sum "$seatDir/brief.md" | cut -d ' ' -f 1)"
      local datom="Start.{ { $launchId [ { brief.md $briefHash } ] [] Psyche Low Codex $codexModel low None [] $herdrSession «$bundle» «Report ready.» } { pt0000 message-flow-$runId case-codex } }"
      say "case codex — endpoint $codexClient — expect started"
      say "  command: flow '$datom'"
      say "  revision: $flowRevision"
      held "$caseDirectory/start.reply" timeout 900 env -i FLOW_SOCKET="$flowRuntime/${flow.ordinarySocket}" ${flow.client} "$datom"
      if grep -q '^StartAmbiguous' "$caseDirectory/start.reply"; then
        held "$caseDirectory/observe.txt" timeout "$(promotionWait started)" env -i FLOW_SOCKET="$flowRuntime/${flow.ordinarySocket}" ${flow.client} "Observe.Launch.$launchId"
      fi
      flowCall "LaunchStatus.$launchId" >"$caseDirectory/final.reply" 2>&1 || true
      local facts verdict flowIdentity pane
      facts="$(${oracle} reply "$caseDirectory/start.reply" "$caseDirectory/final.reply")"
      verdict="$(jq -r '.verdict // "none"' <<<"$facts")"
      flowIdentity="$(jq -r '.flow_id // ""' <<<"$facts")"
      pane="$(jq -r '.pane_id // ""' <<<"$facts")"
      say "  flow verdict: $verdict; flow $flowIdentity"
      if [ "$verdict" != Started ] || [ -z "$flowIdentity" ]; then
        failures=$((failures + 1))
        say "  result: FAILED: Flow said $verdict"
        return
      fi
      flowCall 'List.{ }' >"$caseDirectory/list-before.reply" 2>&1 || true
      say "  list before stop: $flowIdentity is $(${oracle} lifecycle "$caseDirectory/list-before.reply" "$flowIdentity")"
      flowCall "Stop.$flowIdentity" >"$caseDirectory/stop.reply" 2>&1 || true
      say "  stop: $(tr '\n' ' ' <"$caseDirectory/stop.reply")"
      flowCall 'List.{ }' >"$caseDirectory/list-after.reply" 2>&1 || true
      local after
      after="$(${oracle} lifecycle "$caseDirectory/list-after.reply" "$flowIdentity")"
      say "  list after stop: $flowIdentity is $after"
      if [ "$after" = Stopped ] && ! herdrCall pane get "$pane" >/dev/null 2>&1; then
        say "  result: ok: started, listed, stopped, pane gone (the Codex seat's process is not observed)"
      else
        failures=$((failures + 1))
        say "  result: FAILED: after stop the flow is $after or its pane $pane remains"
      fi
    }

    if [ "$mode" = live-codex ]; then
      runLiveCodex
      say "cases failed: $failures"
      [ "$failures" -eq 0 ]
      exit
    fi

    # --- the cases -------------------------------------------------------
    # Only the stand-in reaches here: live-claude refuses above.
    harnessSeat="stand-in faithful"
    longLine=""
    for _ in $(seq 1 13); do
      longLine+="This sentence pads the long first prompt past eight hundred units. "
    done
    longLine+="Report ready."
    twoLines="$(printf 'Report your two-line status.\nNothing else.')"

    runCase A "$harnessSeat" started direct false "''${skills[@]}" -- "$twoLines"
    runCase B "$harnessSeat" started direct true "''${skills[@]}" -- "$longLine"
    runCase C "$harnessSeat" started stacked false "''${skills[@]}" -- "Report ready."
    runCase D "$harnessSeat" unloaded-skill stacked false spirit absent-skill-message-flow operational-final-response -- "Report ready."
    runCase E "stand-in other-model" model direct false "''${skills[@]}" -- "$twoLines"
    runCase F "stand-in footer-dropped" footer-present direct false "''${skills[@]}" -- "$twoLines"
    runCase J "stand-in body-altered" prompt-hash direct false "''${skills[@]}" -- "$twoLines"

    say "not written: four of the eleven planned cases. This run covers seven (A B C D E F J)."
    say "  G  a foreign entry in the pane before Flow's first prompt"
    say "  H  a message delivered into the seat after its receipt"
    say "  I  a start left ambiguous under Flow 0.17.3, re-checked under 0.17.4"
    say "  K  a second identical first-prompt entry, which 0.17.4 is known to accept"
    say "worth: every seat of this run was the stand-in; it proves the scenario's logic and nothing about a real harness."
    say "cases failed: $failures"
    [ "$failures" -eq 0 ]
  '';
}
