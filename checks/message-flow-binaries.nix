# A pure scenario: the two pinned components deliver the binaries every
# message-flow scenario drives. It runs in the build sandbox with no network and
# no credentials — it only realises the pinned packages and looks at them.
{
  pkgs,
  flake,
  system,
  ...
}:
let
  flow = flake.lib.components.flow.forSystem system;
  message = flake.lib.components.message.forSystem system;
in
pkgs.runCommand "message-flow-binaries" { } ''
  for binary in ${flow.nexus} ${flow.client} ${flow.metaClient} \
                ${message.nexus} ${message.client} ${message.metaClient}; do
    test -x "$binary" || { echo "not executable: $binary" >&2; exit 1; }
  done
  touch $out
''
