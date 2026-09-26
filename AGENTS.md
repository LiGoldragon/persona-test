# AGENTS.md

Read the `compensation-nix` skill before writing anything here, and
`compensation-nix-rationale` before discussing this repository's shape.

## What this repository is

The test twin of `persona`. It contains **no component source**. Every tested
repository is a pinned flake input whose `nixpkgs` follows this flake's:

    inputs.flow.url = "github:LiGoldragon/flow/<rev>";
    inputs.flow.inputs.nixpkgs.follows = "nixpkgs";

Tests belong here and not in the tested repository's flake, because an edited
test in that flake changes its source and rebuilds its Rust on a push that
touched no Rust.

## Rules

- One file holds one scenario, component, or builder.
- Name a scenario by its components, hyphen-joined, in drive order.
- A scenario takes its components from `flake.lib.components` and adds only its
  own drive and assertions. New component behaviour goes in
  `lib/components/<name>.nix`.
- Name every package as `pkgs.<name>`; never `with pkgs;`.
- A pure scenario is a check: no network, no credentials.
- A semi-sandbox is a `packages/<scenario>.nix` runner with a `mktemp -d` state
  root and an exit trap. Never a check, never `__impure`, never `__noChroot`.
- Run `nix fmt` before every commit. `pkgs.nixfmt` takes files, not a
  directory, so format the tree with
  `find . -name '*.nix' -exec nix fmt {} +` (or pass the paths you touched).
- Evaluate before building:
  `nix flake check --no-build --option allow-import-from-derivation false`,
  then `nix flake check`.
- After each push, run `nix flake check github:LiGoldragon/persona-test`, and
  any semi-sandbox changed as `nix run github:LiGoldragon/persona-test#<scenario>`.
