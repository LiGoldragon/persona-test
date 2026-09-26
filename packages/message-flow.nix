# message-flow — the Flow + Message semi-sandbox runner.
#
# Run it as `nix run .#message-flow`. It is a runner, never a check: each
# tested Nexus gets its own isolated HOME/XDG_RUNTIME_DIR/state/sockets under
# a fresh state root, and any seat Flow launches gets its own isolated
# identity too — its credential files copied in, everything else generated
# fresh (see `flake.lib.seatCredentialEnv`) — removed in an exit trap. No
# config file is ever copied.
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

  meta.description = "Flow 0.16 + Message 0.16 semi-sandbox: each Nexus and any seat it launches isolated on its own generated identity, driven with the cheapest model.";

  text = ''
    realHome="$HOME"
    realRuntimeDir="''${XDG_RUNTIME_DIR:-}"
    model="''${PERSONA_TEST_MODEL:-${flake.lib.cheapestModel.claude}}"

    ${flake.lib.isolatedStateRoot}

    ${flake.lib.isolatedComponentEnv "flow"}
    ${flake.lib.isolatedComponentEnv "message"}
    ${flake.lib.seatCredentialEnv}

    # Flow's own state is isolated; any seat it launches gets the generated
    # identity above, never the living's real ~/.claude.json or
    # ~/.codex/config.toml.
    export HOME="$flowHome"
    export XDG_RUNTIME_DIR="$flowRuntime"
    export CODEX_HOME="$seatCodexHome"
    export CLAUDE_CONFIG_DIR="$seatHome/.claude"
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
    #   $seatHome/$seatCodexHome/$seatDir   the seat identity a Flow-launched
    #                      Claude or Codex sees; $seatHome/.claude.json and
    #                      $seatCodexHome/config.toml are plain writable
    #                      files, not store paths, so a seat may write back
    #                      to them during the run.
    #   $stateRoot         the isolated root, removed on exit
    #
    # Left for the suite move: Herdr's own config and allowlist for the
    # sandbox's session — Flow launches seats through Herdr, whose
    # executable allowlist and per-session config are not yet generated
    # here, only Claude's and Codex's own files.
    echo "message-flow: skeleton only — Flow on $flowRuntime, Message on $messageRuntime, seat on $seatDir, model $model"
    # --------------------------------------------------------------------

    export XDG_RUNTIME_DIR="$messageRuntime"
    ${message.stop}
    export XDG_RUNTIME_DIR="$flowRuntime"
    ${flow.stop}
  '';
}
