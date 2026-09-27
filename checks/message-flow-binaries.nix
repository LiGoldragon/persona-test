# A pure scenario: the pinned components deliver the binaries every
# message-flow scenario drives, and the stand-in and oracle programs are
# valid Python. It runs in the build sandbox with no network and no
# credentials — it only realises the pinned packages and looks at them.
{
  pkgs,
  flake,
  system,
  ...
}:
let
  inherit (flake.lib) components;
  flow = components.flow.forSystem system;
  message = components.message.forSystem system;
  herdr = components.herdr.forSystem system;
  flowId = components.flow-id.forSystem system;
  seat = components.claude-stand-in.forSystem system;
in
pkgs.runCommand "message-flow-binaries" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  for binary in ${flow.nexus} ${flow.client} ${flow.metaClient} \
                ${message.nexus} ${message.client} ${message.metaClient} \
                ${herdr.executable} ${flowId.executable} \
                ${seat.dispatcher}/bin/claude ${seat.standIn}/bin/claude; do
    test -x "$binary" || { echo "not executable: $binary" >&2; exit 1; }
  done
  test -f ${herdr.claudeHook}
  python3 -m py_compile ${../fixtures/message-flow/oracle.py} ${../fixtures/message-flow/stand_in.py}
  touch $out
''
