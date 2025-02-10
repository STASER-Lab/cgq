{
  description = "build and run cgq";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-gleam.url = "github:arnarg/nix-gleam";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-gleam,
    }:
    {
      overlays = {
        default = nixpkgs.lib.composeManyExtensions [
          nix-gleam.overlays.default
        ];
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;

        default = pkgs.buildGleamApplication {
          src = ./.;
          erlangPackage = pkgs.erlang_27;
        };

        gleamToml = fromTOML (builtins.readFile (./gleam.toml));

        name = gleamToml.name;
        version = gleamToml.version;

        deps = pkgs.callPackage ./deps.nix { erlang = pkgs.erlang_27; };

        mix_gleam = pkgs.fetchFromGitHub {
          owner = "gleam-lang";
          repo = "mix_gleam";
          tag = "v0.6.2";
          sha256 = "sha256-m7fJvMxfGn+kQObZscmNLITLtv9yStUT2nKRKXqCzrs=";
        };

        release = pkgs.stdenv.mkDerivation {
          pname = name;
          inherit version;
          src = ./.;

          nativeBuildInputs = [
            pkgs.elixir
            pkgs.erlang_27
            pkgs.zig
            pkgs.p7zip
            pkgs.cacert
            pkgs.beam.packages.erlang_27.rebar3
          ];

          env = {
            MIX_ENV = "prod";
            HEX_OFFLINE = 1;
            GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            LANG = "C.UTF-8";
            LC_ALL = "C.UTF-8";
            MIX_PATH = "${pkgs.beam.packages.erlang_27.hex}/lib/erlang/lib/hex/ebin";
            MIX_REBAR3 = "${pkgs.beam.packages.erlang_27.rebar3}/bin/rebar3";
          };

          configurePhase = ''
            export HOME=$(mktemp -d)
            mkdir -p $HOME/.mix/archives

            export MIX_HOME=$HOME/.mix

            echo "installing archive"
            tmpdir=$(mktemp -d)
            cp -r ${mix_gleam}/* $tmpdir/
            cd $tmpdir
            mix do archive.build, archive.install --force
            cd -

            echo "installing rebar3"
            mix local.rebar rebar3 ${pkgs.beam.packages.erlang_27.rebar3} --force

            echo "linking deps"

            ln -sfn ${deps}/deps deps

            echo "linked"
          '';

          buildPhase = ''
            mix compile
            mix release
            ls
          '';

          installPhase = ''
            ls
            mkdir -p $out
            cp -r burrito_out/* $out/
          '';
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
