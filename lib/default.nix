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
  # `mktemp -d` and an exit trap that removes it. It does not touch HOME or
  # XDG_RUNTIME_DIR itself — the living's logins are used in place, exactly
  # as tools/flow-message-sandbox does; only the components under test are
  # isolated, with `isolatedComponentEnv` below.
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
  # onto the component's own start/stop/client calls, never onto the whole
  # script, so seats (Claude, Codex, Herdr) launched elsewhere in the same
  # run keep the living's real HOME, in place.
  isolatedComponentEnv = name: ''
    ${name}Home="$stateRoot/${name}/home"
    ${name}Runtime="$stateRoot/${name}/run"
    mkdir -p "$${name}Home" "$${name}Runtime"
    chmod 700 "$${name}Runtime"
  '';

  # The cheapest model per harness, the semi-sandbox default.
  cheapestModel = {
    claude = "claude-haiku-4-5";
    codex = "luna";
  };
}
