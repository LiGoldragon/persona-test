# The seat's `claude`: what Herdr runs when Flow asks it to start a Claude
# agent in a pane. Herdr types `claude <arguments>` into the pane's shell, so
# the seat is whichever `claude` comes first on the pane's PATH. That is the
# dispatcher here, and it chooses, for each start, from the one-line choice
# file the scenario writes before that start:
#
#   real <absolute path>        exec the real Claude harness at that path
#   stand-in <behaviour>        exec the stand-in below
#
# THE STAND-IN IS NOT CLAUDE. It is a small program that draws enough of a
# Claude screen for Herdr to see an idle Claude agent, reports its session to
# Herdr the way Herdr's own Claude hook does, and writes a transcript of the
# shape Claude Code writes, as Flow 0.17.4's observer reads it. It exists so
# that the scenario's own logic — its world, its drive, its oracle — can be
# checked without the living's login. A run on the stand-in witnesses nothing
# about the Claude harness. Its behaviours:
#
#   faithful          records the typed prompt as typed
#   other-model       answers the receipt under another model
#   footer-dropped    records the prompt with Flow's receipt footer cut off
#   body-altered      records the prompt with the footer kept and one byte
#                     of the body before it changed
{ inputs }:
{
  name = "claude-stand-in";

  forSystem =
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    in
    rec {
      # Named `bin/claude` so that Herdr, reading the python process's
      # arguments, recognises the script as Claude.
      standIn = pkgs.writeTextFile {
        name = "claude-stand-in";
        destination = "/bin/claude";
        executable = true;
        text =
          "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ../../fixtures/message-flow/stand_in.py;
      };

      dispatcher = pkgs.writeTextFile {
        name = "claude-seat-dispatcher";
        destination = "/bin/claude";
        executable = true;
        text = ''
          #!${pkgs.bash}/bin/bash
          set -eu
          choiceFile="''${PERSONA_TEST_SEAT_CHOICE:?no seat choice file in this pane}"
          read -r kind argument <"$choiceFile"
          case "$kind" in
            real)
              case "$argument" in
                /*) exec "$argument" "$@" ;;
              esac
              echo "seat dispatcher: real harness path is not absolute: $argument" >&2
              exit 64
              ;;
            stand-in)
              export PERSONA_TEST_STAND_IN_BEHAVIOUR="$argument"
              exec ${standIn}/bin/claude "$@"
              ;;
          esac
          echo "seat dispatcher: unknown seat choice: $kind" >&2
          exit 64
        '';
      };

      binDirectory = "${dispatcher}/bin";
    };
}
