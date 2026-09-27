# Herdr: a headless Herdr server for one named session, with its own
# configuration home, taken from the pinned `herdr` input (v0.8.2).
#
# `herdr --session <name> server` runs the headless server. Herdr resolves a
# session's socket as `$XDG_CONFIG_HOME/herdr/sessions/<name>/herdr.sock`, and
# an explicit `--session` wins over any socket variable, so every call below
# names this run's session and runs under `env -i` with this run's
# XDG_CONFIG_HOME. Nothing here names, lists, or reaches another session.
#
# The server is started under an environment written out in full: it is the
# environment every pane inherits, so a seat's HOME, CLAUDE_CONFIG_DIR and
# PATH are the ones given here. Nothing here reads, sets, or strips the
# variable Herdr uses to mark a process as inside a pane.
#
# No Herdr subcommand is ever run with a help option: a help option given to
# a session subcommand has created a session named by the option.
{ inputs }:
{
  name = "herdr";

  forSystem = system: rec {
    package = inputs.herdr.packages.${system}.herdr;
    revision = inputs.herdr.rev;
    binDirectory = "${package}/bin";
    executable = "${binDirectory}/herdr";

    # The official Claude integration hook of this very revision: it reports
    # a Claude session to Herdr on SessionStart. Real mode installs it in the
    # seat's generated settings; the stand-in reports the same request itself.
    claudeHook = "${inputs.herdr}/src/integration/assets/claude/herdr-agent-state.sh";

    # Needs, absolute: $herdrConfigHome, $herdrStateHome, $herdrRuntime,
    # $herdrLog, and the pane environment $seatHome, $seatClaudeConfigDir,
    # $seatPath, $seatShell, $seatChoiceFile; and $herdrSession.
    start = ''
      for herdrVariable in herdrConfigHome herdrStateHome herdrRuntime herdrLog seatHome seatClaudeConfigDir seatShell seatChoiceFile; do
        requireAbsolute "$herdrVariable" "''${!herdrVariable:-}"
      done
      mkdir -p "$herdrConfigHome" "$herdrStateHome" "$herdrRuntime"
      chmod 700 "$herdrRuntime"
      env -i \
        HOME="$seatHome" \
        XDG_CONFIG_HOME="$herdrConfigHome" \
        XDG_STATE_HOME="$herdrStateHome" \
        XDG_RUNTIME_DIR="$herdrRuntime" \
        CLAUDE_CONFIG_DIR="$seatClaudeConfigDir" \
        PERSONA_TEST_SEAT_CHOICE="$seatChoiceFile" \
        PATH="$seatPath" \
        SHELL="$seatShell" \
        TERM=xterm-256color \
        LANG=C.UTF-8 \
        ${executable} --session "$herdrSession" server >"$herdrLog" 2>&1 &
      herdrServerPid=$!
      awaitSocket "$herdrConfigHome/herdr/sessions/$herdrSession/herdr.sock" "$herdrServerPid" herdr-server
    '';

    # One Herdr CLI call against this run's session and no other.
    call = ''
      herdrCall() {
        env -i \
          HOME="$seatHome" \
          XDG_CONFIG_HOME="$herdrConfigHome" \
          XDG_STATE_HOME="$herdrStateHome" \
          PATH="$seatPath" \
          LANG=C.UTF-8 \
          ${executable} --session "$herdrSession" "$@"
      }
    '';

    stop = ''
      if [ -n "''${herdrServerPid:-}" ]; then
        herdrCall server stop >/dev/null 2>&1 || true
        for _ in $(seq 1 100); do
          kill -0 "$herdrServerPid" 2>/dev/null || break
          sleep 0.1
        done
        kill "$herdrServerPid" 2>/dev/null || true
        wait "$herdrServerPid" 2>/dev/null || true
        herdrServerPid=""
      fi
    '';
  };
}
