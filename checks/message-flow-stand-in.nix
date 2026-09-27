# The message-flow runner in its stand-in mode, inside the build sandbox: no
# network, no login, no credential, no service outside the sandbox. Its own
# Flow, Message and Herdr run under a root below the sandbox's build
# directory and end with it. It checks the scenario's own logic — world,
# drive, oracle, and that the must-fail cases fail for the reason the
# transcript shows. It witnesses nothing about the Claude harness: the seat
# is the stand-in, which is not Claude.
{
  pkgs,
  perSystem,
  ...
}:
pkgs.runCommand "message-flow-stand-in"
  {
    nativeBuildInputs = [ pkgs.coreutils ];
  }
  ''
    # The sandbox has no /tmp; the build directory is short and absolute.
    export PERSONA_TEST_ROOT_BASE="$TMPDIR"
    timeout 900 ${perSystem.self.message-flow}/bin/message-flow stand-in
    touch $out
  ''
