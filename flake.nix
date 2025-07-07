{
  description = "build and run cgq";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    nix-gleam.url = "github:arnarg/nix-gleam";
    nix-gleam-burrito.url = "github:ethanthoma/nix-gleam-burrito";
  };

  outputs =
    inputs@{ ... }:

    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devshell.flakeModule
        inputs.flake-parts.flakeModules.modules
      ];

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "i686-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      perSystem =
        { system, ... }:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system}.extend (
            inputs.nixpkgs.lib.composeManyExtensions [
              inputs.nix-gleam.overlays.default
              inputs.nix-gleam-burrito.overlays.default
            ]
          );
        in
        {
          _module.args.pkgs = pkgs;

          apps = {
            default = pkgs.buildGleamApplication {
              src = ./.;
              erlangPackage = pkgs.erlang_27;
            };

            release = pkgs.buildGleamBurrito {
              src = ./.;
              erlangPackage = pkgs.erlang_27;
            };
          };

          devshells.default = {
            env = [
              {
                name = "MIX_ENV";
                value = "prod";
              }
            ];

            packages = [
              pkgs.erlang_27
              pkgs.elixir
              pkgs.zig
              pkgs.p7zip
              pkgs.mix2nix
              pkgs.gemini-cli
            ];

            commands = [ { package = pkgs.gleam; } ];
          };
        };
    };
}
