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
  # `mktemp -d`, HOME and XDG_RUNTIME_DIR pointed into it, and an exit trap
  # that removes it. Credentials copied in later reach only this root.
  isolatedStateRoot = ''
    stateRoot="$(mktemp -d -t persona-test-XXXXXXXX)"
    cleanup() {
      chmod -R u+w "$stateRoot" 2>/dev/null || true
      rm -rf "$stateRoot"
    }
    trap cleanup EXIT
    export HOME="$stateRoot/home"
    export XDG_RUNTIME_DIR="$stateRoot/run"
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
  '';

  # The cheapest model per harness, the semi-sandbox default.
  cheapestModel = {
    claude = "claude-haiku-4-5";
    codex = "luna";
  };
}
