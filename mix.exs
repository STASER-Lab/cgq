defmodule CGQ.MixProject do
  use Mix.Project

  def project do
    [
      app: :cgq,
      version: "1.0.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      archives: [mix_gleam: "~> 0.6"],
      compilers: [:gleam | Mix.compilers()],
      aliases: [
        "deps.get": ["deps.get", "gleam.deps.get"]
      ],
      erlc_paths: [
        "build/dev/erlang/cgq/_gleam_artefacts",
        "lib",
      ],
      erlc_include_path: "build/dev/erlang/cgq/include",
      prune_code_paths: false,
    ]
  end

  def releases do
    [
      cgq: [
        include_executables_for: [:unix, :windows],
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos: [os: :darwin, cpu: :x86_64],
            linux: [os: :linux, cpu: :x86_64],
            windows: [os: :windows, cpu: :x86_64]
          ]
        ],
        applications: [
          inets: :permanent,
          ssl: :permanent
        ],
        debug: Mix.env() != :prod,
        no_clean: false
      ]
    ]
  end

  def application do
    [ 
      mod: {CGQ.Application, []},
      extra_applications: [:inets, :ssl]
    ]
  end

  defp deps do
    [
      {:argv, ">= 1.0.2 and < 2.0.0"},
      {:birl, ">= 1.8.0 and < 2.0.0"},
      {:clip, ">= 1.0.0 and < 2.0.0"},
      {:envoy, ">= 1.0.2 and < 2.0.0"},
      {:gleam_http, ">= 3.7.2 and < 4.0.0"},
      {:gleam_httpc, ">= 4.0.0 and < 5.0.0"},
      {:gleam_json, ">= 2.3.0 and < 3.0.0"},
      {:gleam_otp, ">= 0.16.1 and < 1.0.0" },
      {:gleam_stdlib, ">= 0.34.0 and < 2.0.0"},
      {:trellis, ">= 2.0.0 and < 3.0.0"},
      {:burrito, "~> 1.0"},
    ]
  end
end
