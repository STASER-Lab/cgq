{
  description = "build and run cgq";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-gleam.url = "github:arnarg/nix-gleam";
    nix-gleam-burrito.url = "github:ethanthoma/nix-gleam-burrito";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-gleam,
      nix-gleam-burrito,
    }:
    {
      overlays = {
        default = nixpkgs.lib.composeManyExtensions [
          nix-gleam.overlays.default
          nix-gleam-burrito.overlays.default
        ];
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;

        erlangPackage = pkgs.erlang_27;

        default = pkgs.buildGleamApplication {
          src = ./.;
          inherit erlangPackage;
        };

        release = pkgs.buildGleamBurrito {
          src = ./.;
          inherit erlangPackage;
        };

        build-deps = [
          pkgs.elixir
          pkgs.zig
          pkgs.p7zip
        ];
      in
      {
        checks = {
          inherit default;
        };

        packages = {
          inherit default;
          inherit release;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ default ];

          packages = build-deps ++ [ pkgs.mix2nix ];

          env.MIX_ENV = "prod";
        };
      }
    );
}
