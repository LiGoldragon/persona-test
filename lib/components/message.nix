# Message: the Message Nexus and its `message` / `message-meta` clients, taken
# from the pinned `message` input. It keeps its store under HOME and its
# sockets under XDG_RUNTIME_DIR, and reaches Flow over Flow's sockets in the
# same runtime directory, so one isolated root holds both components.
{ inputs }:
{
  name = "message";

  forSystem = system: rec {
    package = inputs.message.packages.${system}.default;

    nexus = "${package}/bin/message-nexus";
    client = "${package}/bin/message";
    metaClient = "${package}/bin/message-meta";

    ordinarySocket = "message/message.sock";
    metaSocket = "message/message-owner.sock";

    start = ''
      mkdir -p "$XDG_RUNTIME_DIR/message" "$HOME/.local/state/message"
      ${nexus} &
      messageNexusPid=$!
      for _ in $(seq 1 100); do
        test -S "$XDG_RUNTIME_DIR/${ordinarySocket}" && break
        sleep 0.1
      done
      test -S "$XDG_RUNTIME_DIR/${ordinarySocket}"
    '';

    stop = ''
      kill "$messageNexusPid" 2>/dev/null || true
      wait "$messageNexusPid" 2>/dev/null || true
    '';
  };
}
