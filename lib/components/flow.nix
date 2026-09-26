# Flow: the Flow Nexus and its `flow` / `flow-meta` clients, taken from the
# pinned `flow` input. Isolation is by environment only — the Nexus reads HOME
# for its state and XDG_RUNTIME_DIR for its sockets — so a scenario points both
# at its own root and never touches the living's Flow.
{ inputs }:
{
  name = "flow";

  forSystem = system: rec {
    package = inputs.flow.packages.${system}.default;

    nexus = "${package}/bin/flow-nexus";
    client = "${package}/bin/flow";
    metaClient = "${package}/bin/flow-meta";

    # Relative to XDG_RUNTIME_DIR, as flow-nexus derives them.
    ordinarySocket = "flow/flow.sock";
    metaSocket = "flow/flow-meta.sock";

    # Starts the Nexus against the caller's already-exported HOME and
    # XDG_RUNTIME_DIR, records its pid in `flowNexusPid`, and waits for the
    # ordinary socket to appear.
    start = ''
      mkdir -p "$XDG_RUNTIME_DIR/flow"
      ${nexus} &
      flowNexusPid=$!
      for _ in $(seq 1 100); do
        test -S "$XDG_RUNTIME_DIR/${ordinarySocket}" && break
        sleep 0.1
      done
      test -S "$XDG_RUNTIME_DIR/${ordinarySocket}"
    '';

    stop = ''
      kill "$flowNexusPid" 2>/dev/null || true
      wait "$flowNexusPid" 2>/dev/null || true
    '';
  };
}
