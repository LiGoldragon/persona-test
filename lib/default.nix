{ inputs, ... }:
{
  # One entry per tested component. A scenario reaches these as
  # `flake.lib.components.<name>`, takes what it needs, and adds only its own
  # drive and assertions. Swapping or adding a component in a scenario is a
  # one-line change here.
  components = {
    flow = import ./components/flow.nix { inherit inputs; };
    message = import ./components/message.nix { inherit inputs; };
  };

  # A semi-sandbox's shared shell prelude: a fresh state root under
  # `mktemp -d` and an exit trap that removes it. Every isolated home below —
  # a tested component's or a seat's — lives under it and is removed with it.
  isolatedStateRoot = ''
    stateRoot="$(mktemp -d -t persona-test-XXXXXXXX)"
    cleanup() {
      chmod -R u+w "$stateRoot" 2>/dev/null || true
      rm -rf "$stateRoot"
    }
    trap cleanup EXIT
  '';

  # One tested component's isolated home, runtime dir and sockets, under
  # `$stateRoot/<name>`. Nothing is copied into it: a scenario exports these
  # onto the component's own start/stop/client calls.
  isolatedComponentEnv = name: ''
    ${name}Home="$stateRoot/${name}/home"
    ${name}Runtime="$stateRoot/${name}/run"
    mkdir -p "$${name}Home" "$${name}Runtime"
    chmod 700 "$${name}Runtime"
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

  # The cheapest model per harness, the semi-sandbox default.
  cheapestModel = {
    claude = "claude-haiku-4-5";
    codex = "luna";
  };
}
