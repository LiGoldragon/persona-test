{ inputs, ... }:
{
  # One entry per tested component. A scenario reaches these as
  # `flake.lib.components.<name>`, takes what it needs, and adds only its own
  # drive and assertions. Swapping or adding a component in a scenario is a
  # one-line change here.
  components = {
    flow = import ./components/flow.nix { inherit inputs; };
    message = import ./components/message.nix { inherit inputs; };
    herdr = import ./components/herdr.nix { inherit inputs; };
    flow-id = import ./components/flow-id.nix { inherit inputs; };
    claude-stand-in = import ./components/claude-stand-in.nix { inherit inputs; };
  };

  # Shell helpers every semi-sandbox uses before it starts anything.
  #   requireAbsolute NAME VALUE   refuse to go on unless VALUE is absolute
  #   requireSocketLength PATH     refuse a socket path over the 107 bytes
  #                                an AF_UNIX address can carry
  #   awaitSocket PATH PID NAME    wait for PATH to become a socket while PID
  #                                lives; fail if PID dies or 30 s pass
  shellHelpers = ''
    requireAbsolute() {
      case "$2" in
        /*) ;;
        *)
          echo "refusing: $1 is unset or not absolute: '$2'" >&2
          exit 70
          ;;
      esac
    }
    requireSocketLength() {
      requireAbsolute socket "$1"
      if [ "$(printf '%s' "$1" | wc -c)" -gt 107 ]; then
        echo "refusing: socket path over 107 bytes: $1" >&2
        exit 70
      fi
    }
    awaitSocket() {
      for _ in $(seq 1 300); do
        if [ -S "$1" ]; then
          return 0
        fi
        if ! kill -0 "$2" 2>/dev/null; then
          echo "$3 exited before $1 appeared" >&2
          return 1
        fi
        sleep 0.1
      done
      echo "$3 did not open $1 within 30 s" >&2
      return 1
    }
  '';

  # A semi-sandbox's shared shell prelude: a fresh state root and a trap on
  # every ending signal that removes it. Every isolated home below — a tested
  # component's or a seat's — lives under it and is removed with it.
  #
  # The root is made under /tmp, not under $TMPDIR: every socket of a run
  # lives under it, an AF_UNIX path carries at most 107 bytes, and a
  # harness's TMPDIR can be long enough to break that. A build sandbox has
  # no /tmp, so a check names its own short base in PERSONA_TEST_ROOT_BASE;
  # it must be absolute. Needs `shellHelpers` first.
  #
  # A scenario may define `beforeRootRemoval` to stop every process it holds
  # by PID and print its report. Cleanup runs once, whichever of EXIT, INT,
  # TERM or HUP ends the run: errexit and nounset are dropped inside it, so
  # no failing step and no unset variable skips the removal. On EXIT the
  # shell keeps the status it was exiting with (the trap calls no `exit`);
  # on a signal the run exits with 128 plus the signal's number, and the
  # EXIT trap that follows finds the cleanup already done.
  isolatedStateRoot = ''
    rootBase="''${PERSONA_TEST_ROOT_BASE:-/tmp}"
    requireAbsolute PERSONA_TEST_ROOT_BASE "$rootBase"
    stateRoot="$(mktemp -d "$rootBase/pt.XXXXXXXX")"
    cleanupDone=""
    cleanup() {
      if [ -n "$cleanupDone" ]; then
        return 0
      fi
      cleanupDone=1
      set +eu
      if declare -F beforeRootRemoval >/dev/null; then
        beforeRootRemoval
      fi
      chmod -R u+w "$stateRoot" 2>/dev/null
      rm -rf "$stateRoot"
    }
    trap cleanup EXIT
    trap 'cleanup; exit 129' HUP
    trap 'cleanup; exit 130' INT
    trap 'cleanup; exit 143' TERM
  '';

  # No seat login is projected. How a test seat gets a Claude or Codex login
  # (a copy of the credential, or a share of the live configuration) awaits
  # the living's ruling; until it is given, nothing here reads, copies or
  # writes a credential, and the live Claude form of message-flow refuses.

  # The cheapest model per harness, the semi-sandbox default. Each is the
  # exact identifier Flow 0.17.4 titles a seat from: its display map knows
  # `claude-haiku-4-5-20251001` and `gpt-6-luna`, not `claude-haiku-4-5` or
  # `luna`, and refuses a start whose model it cannot title.
  cheapestModel = {
    claude = "claude-haiku-4-5-20251001";
    codex = "gpt-6-luna";
  };
}
