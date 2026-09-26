# message-flow — the Flow + Message semi-sandbox runner.
#
# Run it as `nix run .#message-flow`. It is a runner, never a check: it makes a
# fresh state root, copies in at run time only the login files its components
# need, starts both Nexuses against that root, drives the cheapest model, and
# removes the root in an exit trap. Credentials reach only that runtime root.
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

  meta.description = "Flow 0.16 + Message 0.16 semi-sandbox: both Nexuses on an isolated state root, driven with the cheapest model.";

  text = ''
    realHome="$HOME"
    model="''${PERSONA_TEST_MODEL:-${flake.lib.cheapestModel.claude}}"

    ${flake.lib.isolatedStateRoot}

    # Logins copied in at run time, never into the store. Each component names
    # what it needs; a missing file is the scenario's problem, not the
    # runner's, so it is reported rather than silently skipped.
    for login in .claude.json .claude/.credentials.json; do
      if [ -e "$realHome/$login" ]; then
        mkdir -p "$HOME/$(dirname "$login")"
        cp "$realHome/$login" "$HOME/$login"
        chmod 600 "$HOME/$login"
      else
        echo "message-flow: no $login under $realHome" >&2
      fi
    done

    ${flow.start}
    ${message.start}

    # --- scenario: drive and assertions go here -------------------------
    # The sandbox scenario suite for Flow 0.16 + Message 0.16 moves its
    # scenario body into this section, using:
    #   ${flow.client} / ${flow.metaClient}
    #   ${message.client} / ${message.metaClient}
    #   $model             the cheapest model, overridable by PERSONA_TEST_MODEL
    #   $stateRoot         the isolated root, removed on exit
    echo "message-flow: skeleton only — both Nexuses are up on $stateRoot, model $model"
    # --------------------------------------------------------------------

    ${message.stop}
    ${flow.stop}
  '';
}
