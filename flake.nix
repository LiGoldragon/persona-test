{
  description = "persona-test — Nix sandboxes that test Persona's components together. Each tested repository is a pinned flake input; scenarios are named by the components they drive.";

  inputs = {
    nixpkgs.url = "github:LiGoldragon/nixpkgs?ref=main";

    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    # Flow 0.17.4, tag flow-0.17.4, pinned by revision.
    flow.url = "github:LiGoldragon/flow/bc464e5e1b94fcc179af73111f43b69db1f69fc5";
    flow.inputs.nixpkgs.follows = "nixpkgs";

    message.url = "github:LiGoldragon/message/f1843dbaa63f38634dc10d3b28df2f4a482d6d35";
    message.inputs.nixpkgs.follows = "nixpkgs";

    # harness 0.3.4, the revision CriomOS-home pins: it ships `flow-id`, the
    # claim helper Flow runs to mint a started seat's Flow ID.
    harness.url = "github:LiGoldragon/harness/d022427938c0925e55e23dfb2d7ba470bbfea3c1";
    harness.inputs.nixpkgs.follows = "nixpkgs";

    # Herdr v0.8.2, the revision CriomOS-home pins. Upstream, unpatched: the
    # Home patch touches only Codex executable selection.
    herdr.url = "github:herdrdev/herdr/9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c";
    herdr.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: inputs.blueprint { inherit inputs; };
}
