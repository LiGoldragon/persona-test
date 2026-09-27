# Message: the Message Nexus and its `message` / `message-meta` clients, taken
# from the pinned `message` input. It keeps its store under HOME and its
# sockets under XDG_RUNTIME_DIR; it is started under `env -i` with both
# written out, so it never falls back to the host's live paths.
{ inputs }:
{
  name = "message";

  forSystem = system: rec {
    package = inputs.message.packages.${system}.default;
    revision = inputs.message.rev;

    nexus = "${package}/bin/message-nexus";
    client = "${package}/bin/message";
    metaClient = "${package}/bin/message-meta";

    ordinarySocket = "message/message.sock";
    metaSocket = "message/message-owner.sock";

    # Needs, absolute: $messageHome, $messageRuntime, $messageLog.
    start = ''
      for messageVariable in messageHome messageRuntime messageLog; do
        requireAbsolute "$messageVariable" "''${!messageVariable:-}"
      done
      mkdir -p "$messageRuntime/message" "$messageHome/.local/state/message"
      chmod 700 "$messageRuntime"
      env -i \
        HOME="$messageHome" \
        XDG_RUNTIME_DIR="$messageRuntime" \
        LANG=C.UTF-8 \
        ${nexus} >"$messageLog" 2>&1 &
      messageNexusPid=$!
      awaitSocket "$messageRuntime/${ordinarySocket}" "$messageNexusPid" message-nexus
    '';

    stop = ''
      if [ -n "''${messageNexusPid:-}" ]; then
        kill "$messageNexusPid" 2>/dev/null || true
        wait "$messageNexusPid" 2>/dev/null || true
        messageNexusPid=""
      fi
    '';
  };
}
