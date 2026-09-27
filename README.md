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
`mktemp -d` state root, removed by a trap on every ending signal. How a
test seat gets a login — a copy of the credential, or a share of the live
configuration — awaits the living's ruling. Until it is given, no runner
here reads, copies or writes a credential, and a form that needs a login
refuses. A semi-sandbox is never a check, never `__impure`, never
`__noChroot`.

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
one root made for the run and removed at its end, whichever of EXIT, INT,
TERM or HUP ends it (under `/tmp`, or the absolute `PERSONA_TEST_ROOT_BASE`
a check names): Flow's store and sockets,
Message's, Herdr's configuration home and its session's headless server, the
seat's home and working directory. Every socket path is checked against the
107 bytes an AF_UNIX address carries before anything starts, and every
derived home and runtime directory must lie under the root and not be, or
lie under, a live one of the caller's (`/run/user/<uid>`, the caller's
`XDG_RUNTIME_DIR`, `~/.local/state/flow`, `~/.config/herdr`). The runner
re-executes itself under an emptied environment first, so nothing the caller
exported — HOME, the XDG directories, any Herdr variable — survives into it.
Each component is started under `env -i` with its whole environment written out and every
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
That is **seven of the eleven** planned cases. Not written: **G** a foreign
entry in the pane before Flow's first prompt; **H** a message delivered into
the seat after its receipt; **I** a start left ambiguous under Flow 0.17.3,
re-checked under 0.17.4; **K** a second identical first-prompt entry, which
0.17.4 is known to accept. The printed report says so too. After each: `List`, a typed `Stop`, `List` again, the pane and the seat's
process shown gone. `fixtures/message-flow/oracle.py` reads the seat's own
transcript from disk and judges it without Flow: the first entry byte for
byte, the text less the footer hashed here and compared with the hash Flow
stored, each skill's expansion in order, the model and effort. Flow's
verdict and the transcript must agree; a disagreement fails the run and
says which. The report (command, revision, result per case) is written under
the root and printed at exit, and it states what a stand-in run is worth.

Case D is pinned to one outcome: `StartRejected.RegistrationRefused`, after
Flow reported `RegistrationAcknowledged`, with the seat's transcript present
and holding no first prompt, and the skill found in no catalog Flow reads.
Any other answer fails it. Flow gives the same `RegistrationRefused` when a
skill cannot be resolved and when the prompt intent is not accepted, so
Flow's answer alone does not prove the reason; the catalog check supplies it,
and the report says this.

Case B's route — the first prompt reaching the harness wrapped — is live-only
evidence. Under the stand-in, the route check tests the fixture's own
wrapping rule, and the oracle marks it so; only a live run witnesses it.

Two modes, kept apart:

    nix run .#message-flow                               # stand-in, the default
    nix run .#message-flow -- live-claude                # refuses, see below
    PERSONA_TEST_CODEX_CLIENT=/abs PERSONA_TEST_CODEX_HOME=/abs \
      PERSONA_TEST_CODEX_CONTROL_SOCKET=/abs nix run .#message-flow -- live-codex

- **stand-in** (the default, and the check `message-flow-stand-in`): every
  seat is the stand-in of `lib/components/claude-stand-in.nix`, a small
  program that is **not Claude**. No login, credential or configuration
  directory of the user is read, and no file holding a secret is made. It
  checks the scenario's own logic and **witnesses nothing about any
  harness**.
- **live**, only by hand and refused without its parameters:
  - **live-claude** **refuses**, before it makes a root or starts anything:
    the login route for test seats awaits the living's ruling. The form keeps
    its name and place so the ruled route can be written in it. Once it is,
    A, B, C and D are to run the real Claude harness, and E, F and J stay on
    the stand-in, since each needs a seat that misbehaves in one known way.
    Only that form will witness the Claude harness.
  - **live-codex**: one Codex start, `List`, `Stop`, `List`, on an already
    isolated Codex endpoint the caller names; the runner reads no Codex
    credential. It observes Flow's answers and that the pane is gone after
    the stop. It does **not** observe the Codex seat's process, and no
    transcript oracle is written for Codex yet.

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
