# persona-test

Nix sandboxes that test Persona's components together. This repository holds no
component source: it **pins each tested repository as a flake input** and drives
them. Its scenarios change often; the code they test changes rarely, so keeping
them apart means a new or edited scenario never invalidates a Rust build, and a
component moves forward only when this repository updates its input.

Test unpushed component code with
`--override-input flow path:/git/github.com/LiGoldragon/flow`. Once it lands,
`nix flake update flow` and commit the lock.

## Layout

Laid out for [numtide blueprint](https://numtide.github.io/blueprint), as
CriomOS is: the directory tree *is* the flake's output tree. `flake.nix` holds
only inputs and `outputs = inputs: inputs.blueprint { inherit inputs; };`.

    lib/default.nix            shared builders, reached as flake.lib.<name>
    lib/components/<name>.nix   one component: how to build, configure, start it
    checks/<scenario>.nix       a pure scenario
    packages/<scenario>.nix     a semi-sandbox scenario's runner
    fixtures/<scenario>/        data one scenario reads
    checks/lint.nix             nixfmt --check, deadnix, statix
    formatter.nix               pkgs.nixfmt

## Two kinds of sandbox

A **pure scenario** is a check. It runs in the build sandbox with no network and
no credentials: `pkgs.testers.runNixOSTest` when it needs services or several
machines, `pkgs.runCommand` otherwise.

A **semi-sandbox** needs the living's logins, the network, or a live model, so it
is a runner, not a check: `nix run .#<scenario>`. It makes a fresh state root
with `mktemp -d`, copies in at run time only the login files its components
need, starts every component against that root, drives the cheapest model
(Haiku for Claude, Luna for Codex) unless given another, asserts, and removes
the root in an exit trap. Credentials reach only that runtime root — never the
store. A semi-sandbox is never a check, never `__impure`, never `__noChroot`.

## Naming

A scenario is named by its components joined by hyphens, in the order it drives
them: `message-flow`, `message-flow-spirit`. Adding or swapping a component is a
one-line change against `flake.lib.components`.

## Scenarios

| scenario | kind | components |
| --- | --- | --- |
| `message-flow` | semi-sandbox (`nix run .#message-flow`) | Flow 0.16, Message 0.16 |
| `message-flow-binaries` | pure check | Flow 0.16, Message 0.16 |

## Running

    nix flake check --no-build --option allow-import-from-derivation false
    nix flake check
    nix run .#message-flow

Builds go to the remote builder; never build locally.
