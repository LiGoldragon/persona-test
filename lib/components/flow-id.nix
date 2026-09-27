# flow-id: the claim helper Flow runs after a native session is observed, to
# mint the started seat's six-hex Flow ID under `<source root>/flows`. Taken
# from the pinned `harness` input (0.3.4), which ships it.
{ inputs }:
{
  name = "flow-id";

  forSystem = system: rec {
    package = inputs.harness.packages.${system}.default;
    revision = inputs.harness.rev;
    binDirectory = "${package}/bin";
    executable = "${binDirectory}/flow-id";
  };
}
