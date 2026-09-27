# Herdr: the terminal workspace substrate Flow uses for session and pane
# bindings. A scenario generates its config under its own state root.
{ inputs }:
{
  name = "herdr";

  forSystem = system: rec {
    package = inputs.nixpkgs.legacyPackages.${system}.herdr;
    client = "${package}/bin/herdr";

    # Herdr admits only executables named in this generated allowlist.
    isolatedConfig = codexClient: ''
      herdrConfigHome="$stateRoot/herdr/config"
      mkdir -p "$herdrConfigHome/herdr"
      printf '%s\n' \
        '[agents]' \
        "codex_executables = [ \"${codexClient}\" ]" \
        > "$herdrConfigHome/herdr/config.toml"
      export XDG_CONFIG_HOME="$herdrConfigHome"
    '';
  };
}
