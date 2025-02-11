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

        inputsFrom = builtins.listToAttrs (
          builtins.map (pkg: {
            name = builtins.elemAt (pkgs.lib.splitString "-" pkg.name) 0;
            value = pkg;
          }) default.nativeBuildInputs
        );

        deps = pkgs.callPackage ./deps.nix {
          inherit (inputsFrom) gleam erlang;
        };

        mix_gleam = pkgs.fetchFromGitHub {
          owner = "gleam-lang";
          repo = "mix_gleam";
          tag = "v0.6.2";
          sha256 = "sha256-m7fJvMxfGn+kQObZscmNLITLtv9yStUT2nKRKXqCzrs=";
        };

        systemToBurrito = {
          "x86_64-darwin" = {
            target = "macos";
            os = "darwin";
            cpu = "x86_64";
          };
          "aarch64-darwin" = {
            target = "macos";
            os = "darwin";
            cpu = "aarch64";
          };
          "x86_64-linux" = {
            target = "linux";
            os = "linux";
            cpu = "x86_64";
          };
          "aarch64-linux" = {
            target = "linux";
            os = "linux";
            cpu = "aarch64";
          };
        };

        currentTarget = systemToBurrito.${pkgs.system};

        makeErtsPackage =
          {
            os,
            cpu,
            erlang,
            ...
          }:
          let
            version = erlang.version;
          in
          pkgs.runCommand "otp-${version}-${os}-${cpu}.tar.gz" { } ''
            mkdir -p otp-${version}-${os}-${cpu}
            cd otp-${version}-${os}-${cpu}

            cp -r ${erlang}/lib/erlang/erts* erts-${version}
            cp -r ${erlang}/lib/erlang/releases releases
            cp -r ${erlang}/lib/erlang/lib lib
            cp -r ${erlang}/lib/erlang/misc misc
            cp -r ${erlang}/lib/erlang/usr usr
            touch Install

            cd ..
            tar czf $out otp-${version}-${os}-${cpu}
          '';

        erts_current = makeErtsPackage (
          currentTarget
          // {
            erlang = pkgs.erlang_27;
          }
        );

        release = pkgs.stdenv.mkDerivation {
          pname = name;
          inherit version;
          src = ./.;

          nativeBuildInputs = [
            pkgs.elixir
            pkgs.erlang_27
            pkgs.zig
            pkgs.p7zip
            pkgs.beam.packages.erlang_27.hex
            pkgs.beam.packages.erlang_27.rebar3
          ] ++ default.nativeBuildInputs;

          env = {
            MIX_ENV = "prod";
            HEX_OFFLINE = 1;
            LANG = "C.UTF-8";
            LC_ALL = "C.UTF-8";
            MIX_PATH = "${pkgs.beam.packages.erlang_27.hex}/lib/erlang/lib/hex/ebin";
            MIX_REBAR3 = "${pkgs.beam.packages.erlang_27.rebar3}/bin/rebar3";
            BURRITO_TARGET = currentTarget.target;
          };

          configurePhase = ''
            export HOME=$(mktemp -d)
            mkdir -p $HOME/.mix/archives

            export MIX_HOME=$HOME/.mix

            echo "Updating mix.exs..."
            sed -i \
                -e 's|\[os: :${currentTarget.os}, cpu: :${currentTarget.cpu}\]|[os: :${currentTarget.os}, cpu: :${currentTarget.cpu}, custom_erts: "${erts_current}"]|' \
                mix.exs
            echo "Updated."

            echo "Installing archive..."
            tmpdir=$(mktemp -d)
            cp -r ${mix_gleam}/* $tmpdir/
            cd $tmpdir
            mix do archive.build, archive.install --force
            cd -
            echo "Installed."

            echo "Installing rebar3..."
            mix local.rebar rebar3 ${pkgs.beam.packages.erlang_27.rebar3}/bin/rebar3 --force
            echo "Installed."

            echo "Adding deps..."

            cp -r ${deps}/deps deps
            chmod -R 755 deps

            echo "Added."
          '';

          buildPhase = ''
            mix compile
            mix release
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp burrito_out/* $out/bin/cgq
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
