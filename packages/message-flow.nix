# message-flow — the Flow + Message semi-sandbox runner.
#
# Run it as `nix run .#message-flow`. It is a runner, never a check: it keeps
# the caller's real HOME in place for seats (Claude, Codex, Herdr), and
# isolates only the two Nexuses under test — each gets its own HOME,
# XDG_RUNTIME_DIR, state and sockets under a fresh state root, removed in an
# exit trap. No login file is ever copied.
#
# This is the skeleton. The scenario drive and its assertions belong in the
# marked section below.
{
  pkgs,
  flake,
  system,
  ...
}:
let
  components = flake.lib.components;
  flow = components.flow.forSystem system;
  message = components.message.forSystem system;
in
pkgs.writeShellApplication {
  name = "message-flow";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
  ];

  meta.description = "Flow 0.16 + Message 0.16 semi-sandbox: seats keep the real HOME in place, each Nexus isolated on its own state root, driven with the cheapest model.";

  text = ''
    realHome="$HOME"
    realRuntimeDir="''${XDG_RUNTIME_DIR:-}"
    model="''${PERSONA_TEST_MODEL:-${flake.lib.cheapestModel.claude}}"

    ${flake.lib.isolatedStateRoot}

    ${flake.lib.isolatedComponentEnv "flow"}
    ${flake.lib.isolatedComponentEnv "message"}

    # Flow's own state is isolated; a seat it launches still finds the
    # living's real Codex and Claude trust and credentials, never copied.
    export HOME="$flowHome"
    export XDG_RUNTIME_DIR="$flowRuntime"
    export CODEX_HOME="$realHome/.codex"
    export CLAUDE_CONFIG_DIR="$realHome/.claude"
    ${flow.start}

    export HOME="$messageHome"
    export XDG_RUNTIME_DIR="$messageRuntime"
    unset CODEX_HOME CLAUDE_CONFIG_DIR
    ${message.start}

    export HOME="$realHome"
    export XDG_RUNTIME_DIR="$realRuntimeDir"

    # --- scenario: drive and assertions go here -------------------------
    # The sandbox scenario suite for Flow 0.16 + Message 0.16 moves its
    # scenario body into this section, using:
    #   ${flow.client} / ${flow.metaClient}      reach Flow via:
    #     XDG_RUNTIME_DIR="$flowRuntime" ${flow.client} ...
    #   ${message.client} / ${message.metaClient} reach Message via:
    #     XDG_RUNTIME_DIR="$messageRuntime" ${message.client} ...
    #   $model             the cheapest model, overridable by PERSONA_TEST_MODEL
    #   $realHome          the living's own HOME, where seats run in place
    #   $stateRoot         the isolated root, removed on exit
    echo "message-flow: skeleton only — Flow on $flowRuntime, Message on $messageRuntime, seats on $realHome, model $model"
    # --------------------------------------------------------------------

    export XDG_RUNTIME_DIR="$messageRuntime"
    ${message.stop}
    export XDG_RUNTIME_DIR="$flowRuntime"
    ${flow.stop}
  '';
}
