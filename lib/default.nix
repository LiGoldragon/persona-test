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

  # A semi-sandbox's shared shell prelude: a fresh state root and an exit
  # trap that removes it. Every isolated home below — a tested component's or
  # a seat's — lives under it and is removed with it.
  #
  # The root is made under /tmp, not under $TMPDIR: every socket of a run
  # lives under it, an AF_UNIX path carries at most 107 bytes, and a
  # harness's TMPDIR can be long enough to break that. A build sandbox has
  # no /tmp, so a check names its own short base in PERSONA_TEST_ROOT_BASE;
  # it must be absolute. Needs `shellHelpers` first. A scenario may define
  # `beforeRootRemoval` to stop what it started and print its report; when
  # defined, it runs before the root is removed, on success and on failure
  # alike.
  isolatedStateRoot = ''
    rootBase="''${PERSONA_TEST_ROOT_BASE:-/tmp}"
    requireAbsolute PERSONA_TEST_ROOT_BASE "$rootBase"
    stateRoot="$(mktemp -d "$rootBase/pt.XXXXXXXX")"
    cleanup() {
      if declare -F beforeRootRemoval >/dev/null; then
        beforeRootRemoval || true
      fi
      chmod -R u+w "$stateRoot" 2>/dev/null || true
      rm -rf "$stateRoot"
    }
    trap cleanup EXIT
  '';

  # A seat's isolated identity: `$seatHome`, `$seatCodexHome` and `$seatDir`,
  # every one a writable directory under `$stateRoot/seat`, never a store
  # path or a symlink to one — Claude and Codex both write back into their
  # own config and state at run time, and a seat needs to keep doing that.
  #
  # Only the two credential files are ever copied, and only they: Claude's
  # `.credentials.json` and Codex's `auth.json`. Everything else a seat needs
  # to accept those credentials and trust its own directory is generated
  # here, at run time, from the real login's *non-secret* account fields
  # (`oauthAccount`, read with `jq`, never the whole file) — never a copy of
  # the living's real `~/.claude.json`, `~/.claude/settings.json` or
  # `~/.codex/config.toml`, whose trust entries and allowlists name the
  # living's own directories, not the seat's.
  #
  # `$realHome` and `$model` must already be set by the caller.
  # No heredoc here: nixfmt reindents this string's lines, which would move
  # a heredoc terminator off column zero and break it. Every generated file
  # is written with jq or printf instead, so reindentation is harmless.
  seatCredentialEnv = ''
    seatHome="$stateRoot/seat/home"
    seatCodexHome="$stateRoot/seat/codex"
    seatDir="$stateRoot/seat/work"
    mkdir -p "$seatHome/.claude" "$seatCodexHome" "$seatDir"

    if [ -e "$realHome/.claude/.credentials.json" ]; then
      cp "$realHome/.claude/.credentials.json" "$seatHome/.claude/.credentials.json"
      chmod 600 "$seatHome/.claude/.credentials.json"
    else
      echo "message-flow: no .claude/.credentials.json under $realHome" >&2
    fi
    if [ -e "$realHome/.codex/auth.json" ]; then
      cp "$realHome/.codex/auth.json" "$seatCodexHome/auth.json"
      chmod 600 "$seatCodexHome/auth.json"
    else
      echo "message-flow: no .codex/auth.json under $realHome" >&2
    fi

    # The account fields Claude checks a credential file against — nothing
    # else from the real file, and never its trust entries.
    account="$(jq '{oauthAccount: (.oauthAccount // {})}' "$realHome/.claude.json" 2>/dev/null || echo '{}')"
    jq -n --argjson account "$account" --arg dir "$seatDir" \
      '$account + {
        hasCompletedOnboarding: true,
        projects: { ($dir): {
          allowedTools: [],
          mcpServers: {},
          enabledMcpjsonServers: [],
          disabledMcpjsonServers: [],
          hasTrustDialogAccepted: true,
          hasClaudeMdExternalIncludesApproved: false,
          hasClaudeMdExternalIncludesWarningShown: false
        } }
      }' > "$seatHome/.claude.json"

    jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$seatHome/.claude/settings.json"

    printf '%s\n' \
      'approval_policy = "never"' \
      'sandbox_mode = "danger-full-access"' \
      "model = \"$model\"" \
      "" \
      "[projects.\"$seatDir\"]" \
      'trust_level = "trusted"' \
      > "$seatCodexHome/config.toml"
  '';

  # The cheapest model per harness, the semi-sandbox default. Each is the
  # exact identifier Flow 0.17.4 titles a seat from: its display map knows
  # `claude-haiku-4-5-20251001` and `gpt-6-luna`, not `claude-haiku-4-5` or
  # `luna`, and refuses a start whose model it cannot title.
  cheapestModel = {
    claude = "claude-haiku-4-5-20251001";
    codex = "gpt-6-luna";
  };
}
