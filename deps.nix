{
  stdenv,
  erlang,
  elixir,
  gleam,
  git,
  fetchFromGitHub,
}:

let
  mix_gleam = fetchFromGitHub {
    owner = "gleam-lang";
    repo = "mix_gleam";
    tag = "v0.6.2";
    sha256 = "sha256-m7fJvMxfGn+kQObZscmNLITLtv9yStUT2nKRKXqCzrs=";
  };
in
stdenv.mkDerivation {
  name = "deps";

  src = ./.;

  nativeBuildInputs = [
    erlang
    elixir
    gleam
    git
  ];

  env = {
    MIX_ENV = "PROD";
    LANG = "C.UTF-8";
    LC_ALL = "C.UTF-8";
  };

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";

  outputHash = "sha256-sZ4b6W+G9/YOLnhDTsSFoPJjeiDw/qDsZTVX5Ufb2tc=";

  buildPhase = ''
    export HOME=$(mktemp -d)
    mkdir -p $HOME/.mix/archives

    export MIX_HOME=$HOME/.mix

    mix local.hex --force

    tmpdir=$(mktemp -d)
    cp -r ${mix_gleam}/* $tmpdir/
    cd $tmpdir
    mix do archive.build, archive.install --force

    cd -
    mix deps.get --no-archives-check
    mix gleam.deps.get --no-archives-check
  '';

  installPhase = ''
    mkdir -p $out
    cp -r deps $out/
    cp -r $HOME/.mix $out/
  '';

  dontConfigure = true;
  dontFixup = true;
}
