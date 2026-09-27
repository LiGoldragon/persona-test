# Flow: the Flow Nexus and its `flow` / `flow-meta` clients, taken from the
# pinned `flow` input (0.17.4 at bc464e5e1b94fcc179af73111f43b69db1f69fc5).
# The client and the service come from this one build.
#
# Isolation is by environment only. flow-nexus takes its store from HOME and
# its sockets from XDG_RUNTIME_DIR, and falls back to the host's live paths
# when either is unset or relative; the `flow` client falls back to the live
# socket when FLOW_SOCKET is unset. So the Nexus is started under `env -i`
# with an environment written out here in full, and every client call names
# its socket. Both refuse to run unless every path is absolute.
#
# flow-nexus has no help path: any argument but `--version` alone, or none,
# starts a service. It is only ever started with no argument, as here.
{ inputs }:
{
  name = "flow";

  forSystem = system: rec {
    package = inputs.flow.packages.${system}.default;
    revision = inputs.flow.rev;

    nexus = "${package}/bin/flow-nexus";
    client = "${package}/bin/flow";
    metaClient = "${package}/bin/flow-meta";

    # Relative to the XDG_RUNTIME_DIR flow-nexus is given.
    ordinarySocket = "flow/flow.sock";
    metaSocket = "flow/flow-meta.sock";

    # Needs, all absolute and already made: $flowHome, $flowRuntime,
    # $flowSourceRoot, $flowClaudeConfigDir, $herdrConfigHome,
    # $herdrStateHome, $flowPath (its PATH: Herdr and flow-id), $flowLog;
    # and the array $flowDeploymentOverrides, `NAME=value` words for Flow's
    # own FLOW_* deployment overrides (empty unless a Codex endpoint is
    # given), each checked to name a FLOW_ variable.
    # Sets $flowNexusPid and waits for the ordinary socket, or fails.
    start = ''
      for flowVariable in flowHome flowRuntime flowSourceRoot flowClaudeConfigDir herdrConfigHome herdrStateHome flowLog; do
        requireAbsolute "$flowVariable" "''${!flowVariable:-}"
      done
      for flowOverride in "''${flowDeploymentOverrides[@]}"; do
        case "$flowOverride" in
          FLOW_*=/*) ;;
          FLOW_CODEX_*_MODELS=*) ;;
          *)
            echo "refusing: not an absolute FLOW_ deployment override: $flowOverride" >&2
            exit 70
            ;;
        esac
      done
      mkdir -p "$flowRuntime/flow"
      chmod 700 "$flowRuntime"
      env -i \
        HOME="$flowHome" \
        XDG_RUNTIME_DIR="$flowRuntime" \
        FLOW_SOURCE_ROOT="$flowSourceRoot" \
        CLAUDE_CONFIG_DIR="$flowClaudeConfigDir" \
        CODEX_HOME="$flowHome/.codex" \
        XDG_CONFIG_HOME="$herdrConfigHome" \
        XDG_STATE_HOME="$herdrStateHome" \
        PATH="$flowPath" \
        LANG=C.UTF-8 \
        "''${flowDeploymentOverrides[@]}" \
        ${nexus} >"$flowLog" 2>&1 &
      flowNexusPid=$!
      awaitSocket "$flowRuntime/${ordinarySocket}" "$flowNexusPid" flow-nexus
    '';

    # One Query datom to this run's Flow, and to no other.
    call = ''
      flowCall() {
        requireAbsolute flowRuntime "$flowRuntime"
        env -i FLOW_SOCKET="$flowRuntime/${ordinarySocket}" ${client} "$1"
      }
    '';

    stop = ''
      if [ -n "''${flowNexusPid:-}" ]; then
        kill "$flowNexusPid" 2>/dev/null || true
        wait "$flowNexusPid" 2>/dev/null || true
        flowNexusPid=""
      fi
    '';
  };
}
