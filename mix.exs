defmodule Membrane.WebRTC.Plugin.Mixfile do
  use Mix.Project

  @version "0.25.2"
  @github_url "https://github.com/membraneframework/membrane_webrtc_plugin"

  def project do
    [
      app: :membrane_webrtc_plugin,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),

      # hex
      description: "Membrane WebRTC plugin",
      package: package(),

      # docs
      name: "Membrane WebRTC plugin",
      source_url: @github_url,
      docs: docs()
    ]
  end

  def application do
    [
      mod: {Membrane.WebRTC.App, []},
      extra_applications: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # Phoenix
      {:phoenix, ">= 0.0.0", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},

      # Membrane
      {:membrane_core, "~> 1.2 and >= 1.2.2"},
      {:membrane_rtp_plugin, "~> 0.30.0"},
      {:membrane_rtp_h264_plugin, "~> 0.20.1"},
      {:membrane_rtp_vp8_plugin, "~> 0.9.4"},
      {:membrane_rtp_opus_plugin, "~> 0.10.0"},

      # Other dependencies
      {:ex_webrtc, "~> 0.8.0"},
      {:corsica, "~> 2.0"},
      {:bandit, "~> 1.2"},
      {:websock_adapter, "~> 0.5.0"},
      {:req, "~> 0.5"},
      {:membrane_matroska_plugin, "~> 0.5.0", only: :test},
      {:membrane_mp4_plugin, "~> 0.35.2", only: :test},
      {:membrane_h26x_plugin, "~> 0.10.2", only: :test},
      {:membrane_file_plugin, "~> 0.17.0", only: :test},
      {:membrane_realtimer_plugin, "~> 0.10.0", only: :test},
      {:membrane_opus_plugin, "~> 0.20.0", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp dialyzer() do
    opts = [
      flags: [:error_handling]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      files: ~w(mix.exs lib assets package.json README.md LICENSE),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membrane.stream"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.WebRTC]
    ]
  end
end
