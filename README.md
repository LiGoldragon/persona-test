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
is a runner, not a check: `nix run .#<scenario>`. Every tested component, and
any seat it launches, gets its own isolated identity under a fresh
`mktemp -d` state root, removed in an exit trap. Only the credential files
themselves are copied into it at run time — Claude's `.credentials.json`,
Codex's `auth.json` — never a config file: `~/.claude.json`,
`~/.claude/settings.json` and `~/.codex/config.toml` carry the living's own
trust entries and allowlists, not the seat's, so the runner generates fresh,
writable ones from the real login's non-secret account fields instead. A
semi-sandbox is never a check, never `__impure`, never `__noChroot`.

## Naming

A scenario is named by its components joined by hyphens, in the order it drives
them: `message-flow`, `message-flow-spirit`. Adding or swapping a component is a
one-line change against `flake.lib.components`.

## Scenarios

| scenario | kind | components |
| --- | --- | --- |
| `message-flow` | semi-sandbox runner (`nix run .#message-flow -- <mode>`) | Flow 0.17.4, Message 0.16, Herdr 0.8.2 (Home's patch), flow-id (harness 0.3.4) |
| `message-flow-stand-in` | pure check: the runner in stand-in mode, in the build sandbox | the same, seat is the stand-in |
| `message-flow-binaries` | pure check | the same, plus the stand-in and oracle programs |

### `message-flow`: the Flow 0.17.4 live-start witness

It witnesses whether Flow 0.17.4 (`bc464e5e1b94fcc179af73111f43b69db1f69fc5`)
starts a seat correctly, and leaves nothing behind. Everything lives under
one root made for the run and removed at its end (under `/tmp`, or the
absolute `PERSONA_TEST_ROOT_BASE` a check names): Flow's store and sockets,
Message's, Herdr's configuration home and its session's headless server, the
seat's home and working directory. Every socket path is checked against the
107 bytes an AF_UNIX address carries before anything starts. Each component
is started under `env -i` with its whole environment written out and every
path checked absolute, so none falls back to the host's live store or
sockets; every Flow client call names this run's socket; every Herdr call
names this run's session; every process is stopped by the PID the runner
holds.

One at a time it starts a seat on `claude-haiku-4-5-20251001` at medium
effort, aspect Field, power UltraLow, skills `spirit`, `testing`,
`operational-final-response` (fixtures of this repository), with a first
prompt of **A** two short lines, **B** one line over 800 UTF-16 units, **C**
one short line; and the cases that must fail: **D** a skill that cannot
load, **E** a seat that answers under another model, **F** a first entry
that is not the stored prompt, **J** the footer kept and the body altered.
After each: `List`, a typed `Stop`, `List` again, the pane and the seat's
process shown gone. `fixtures/message-flow/oracle.py` reads the seat's own
transcript from disk and judges it without Flow: the first entry byte for
byte, the text less the footer hashed here and compared with the hash Flow
stored, each skill's expansion in order, the model and effort. Flow's
verdict and the transcript must agree; a disagreement fails the run and
says which. The report (command, revision, result per case) is written under
the root and printed at exit.

Two modes, kept apart:

    nix run .#message-flow                               # stand-in, the default
    nix run .#message-flow -- live-claude /absolute/path/to/claude
    PERSONA_TEST_CODEX_CLIENT=/abs PERSONA_TEST_CODEX_HOME=/abs \
      PERSONA_TEST_CODEX_CONTROL_SOCKET=/abs nix run .#message-flow -- live-codex

- **stand-in** (the default, and the check `message-flow-stand-in`): every
  seat is the stand-in of `lib/components/claude-stand-in.nix`, a small
  program that is **not Claude**. No login, credential or configuration
  directory of the user is read; the login projection
  (`flake.lib.seatCredentialEnv`) is not called. It checks the scenario's
  own logic and **witnesses nothing about any harness**.
- **live**, only by hand and refused without its parameters:
  - **live-claude**: A, B, C and D run the real Claude harness at the given
    path on the seat identity the login projection generates, with Herdr's
    own Claude hook added to the generated settings. **Only this form
    witnesses the Claude harness.** E, F and J run on the stand-in here too:
    each needs a seat that misbehaves in one known way, and they test Flow's
    checks, not the harness.
  - **live-codex**: one Codex start, `List`, `Stop`, `List`, on an already
    isolated Codex endpoint the caller names; the runner reads no Codex
    credential. No transcript oracle is written for Codex yet.

Run a live form as an ordinary program outside any Herdr pane, with a time
limit and a memory cap, for example as a transient unit of the user's
service manager. The runner never reads, sets or strips the variable Herdr
uses to mark a process as inside a pane.

## Running

    find . -name '*.nix' -exec nix fmt {} +
    nix flake check --no-build --option allow-import-from-derivation false
    nix flake check
    nix run .#message-flow

Builds go to the remote builder; never build locally.
