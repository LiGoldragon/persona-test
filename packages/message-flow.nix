# message-flow — the Flow + Herdr + Message semi-sandbox runner.
#
# This runner never reads or copies credentials. A live run receives an
# already-isolated Codex endpoint from its caller; the test state, sockets and
# Herdr allowlist are generated under one fresh root and removed on exit.
{
  pkgs,
  flake,
  system,
  ...
}:
let
  components = flake.lib.components;
  flow = components.flow.forSystem system;
  herdr = components.herdr.forSystem system;
  message = components.message.forSystem system;
in
pkgs.writeShellApplication {
  name = "message-flow";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.gnused
    pkgs.ripgrep
    pkgs.util-linux
    herdr.package
  ];

  meta.description = "Flow 0.17.4 + Herdr + Message semi-sandbox with a bounded Start/List/Stop scenario.";

  text = ''
    model="''${PERSONA_TEST_MODEL:-${flake.lib.cheapestModel.codex}}"
    codexClient="''${PERSONA_TEST_CODEX_CLIENT:?set PERSONA_TEST_CODEX_CLIENT to an isolated Codex executable}"
    codexHome="''${PERSONA_TEST_CODEX_HOME:?set PERSONA_TEST_CODEX_HOME to its isolated home}"
    codexControlSocket="''${PERSONA_TEST_CODEX_CONTROL_SOCKET:?set PERSONA_TEST_CODEX_CONTROL_SOCKET to its isolated control socket}"

    ${flake.lib.isolatedStateRoot}
    ${flake.lib.isolatedComponentEnv "flow"}
    ${flake.lib.isolatedComponentEnv "message"}
    ${herdr.isolatedConfig "$codexClient"}

    herdrHome="$stateRoot/herdr/home"
    mkdir -p "$herdrHome"
    export HOME="$herdrHome"
    script -qfc '${herdr.client} session attach message-flow' /dev/null >/dev/null 2>&1 &
    herdrClientPid=$!
    for _ in $(seq 1 100); do
      ${herdr.client} --session message-flow pane list >/dev/null 2>&1 && break
      sleep 0.1
    done
    ${herdr.client} --session message-flow pane list >/dev/null

    sourceRoot="$stateRoot/source"
    mkdir -p "$sourceRoot"
    printf '%s\n' 'Start, List, and Stop are the bounded message-flow scenario.' > "$sourceRoot/brief.md"
    briefHash="$(sha256sum "$sourceRoot/brief.md" | cut -d ' ' -f 1)"

    # Source assertions: only the generated Herdr config is inherited, and
    # the configured Codex executable is its sole allowlist entry.
    test "$XDG_CONFIG_HOME" = "$herdrConfigHome"
    rg -Fx "codex_executables = [ \"$codexClient\" ]" "$herdrConfigHome/herdr/config.toml"

    export HOME="$flowHome"
    export XDG_RUNTIME_DIR="$flowRuntime"
    export CODEX_HOME="$codexHome"
    export FLOW_SOURCE_ROOT="$sourceRoot"
    ${flow.start}
    FLOW_META_SOCKET="$flowRuntime/${flow.metaSocket}" ${flow.metaClient} "Configure.{ $flowRuntime/${flow.ordinarySocket} $flowRuntime/${flow.metaSocket} $sourceRoot { $codexClient $codexHome $codexControlSocket [ $model ] } { $codexClient $codexHome $codexControlSocket [ $model ] } [ { Codex [ / «!» ] [ esc ] [] } ] [ Psyche ] ${message.nexus} }" | rg -x 'Configured\..*'
    ${flow.stop}
    ${flow.start}

    export HOME="$messageHome"
    export XDG_RUNTIME_DIR="$messageRuntime"
    unset CODEX_HOME
    ${message.start}

    # Start → List → Stop. Flow checks brief.md's exact hash before launch;
    # List observes the row; Stop closes the bound Herdr pane. The supplied
    # endpoint owns any authentication, outside this runner.
    startReply="$(FLOW_SOCKET="$flowRuntime/${flow.ordinarySocket}" ${flow.client} "Start.{ { message-flow-start [ { brief.md $briefHash } ] [] Psyche Low Codex $model low None [] message-flow $sourceRoot/brief.md «FLOW_LAUNCH_RECEIPT_V2» } { owner owner owner } }")"
    printf '%s\n' "$startReply" | rg -x 'Started\..*'
    flowId="$(printf '%s\n' "$startReply" | sed -n 's/^Started\.\({ \)?\([^ }]*\).*/\2/p')"
    test -n "$flowId"
    FLOW_SOCKET="$flowRuntime/${flow.ordinarySocket}" ${flow.client} 'List.{}' | rg -F "$flowId"
    FLOW_SOCKET="$flowRuntime/${flow.ordinarySocket}" ${flow.client} "Stop.$flowId" | rg -x 'Stopped\..*'
    FLOW_SOCKET="$flowRuntime/${flow.ordinarySocket}" ${flow.client} 'List.{}' | rg -F "$flowId" | rg -F 'Stopped'

    export XDG_RUNTIME_DIR="$messageRuntime"
    ${message.stop}
    export XDG_RUNTIME_DIR="$flowRuntime"
    ${flow.stop}
    ${herdr.client} --session message-flow server stop || true
    kill "$herdrClientPid" 2>/dev/null || true
    wait "$herdrClientPid" 2>/dev/null || true
  '';
}
