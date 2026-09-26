{
  description = "persona-test — Nix sandboxes that test Persona's components together. Each tested repository is a pinned flake input; scenarios are named by the components they drive.";

  inputs = {
    nixpkgs.url = "github:LiGoldragon/nixpkgs?ref=main";

    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    flow.url = "github:LiGoldragon/flow/9aa9bf88e3ff6f3b68864eb300ee009897162ef4";
    flow.inputs.nixpkgs.follows = "nixpkgs";

    message.url = "github:LiGoldragon/message/f1843dbaa63f38634dc10d3b28df2f4a482d6d35";
    message.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: inputs.blueprint { inherit inputs; };
}
