defmodule Membrane.WebRTC.Plugin.Mixfile do
  use Mix.Project

  @version "0.1.0-alpha"
  @github_url "https://github.com/membraneframework/membrane_webrtc_plugin"

  def project do
    [
      app: :membrane_webrtc_plugin,
      version: @version,
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description: "Plugin for sending and receiving media with WebRTC",
      package: package(),

      # docs
      name: "Membrane WebRTC plugin",
      source_url: @github_url,
      homepage_url: "https://membraneframework.org",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:membrane_core, "~> 0.7.0"},
      {:qex, "~> 0.5.0"},
      {:bunch, "~> 1.3.0"},
      {:ex_sdp, "~> 0.4.0"},
      {:membrane_rtp_format, "~> 0.3.0"},
      {:membrane_funnel_plugin, "~> 0.2.0"},
      {:membrane_h264_ffmpeg_plugin, "~> 0.9.0"},
      {:membrane_rtp_h264_plugin, "~> 0.5.1"},
      {:membrane_dtls_plugin, "~> 0.4.0"},
      {:membrane_ice_plugin, "~> 0.5.0"},
      {:membrane_rtp_plugin, "~> 0.7.0-alpha"},
      {:ex_libsrtp, "~> 0.1.0"},
      {:membrane_rtp_vp8_plugin, "~> 0.1.0"},
      {:membrane_rtp_opus_plugin, "~> 0.3.0"},
      {:membrane_opus_plugin, "~> 0.5.0"},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.WebRTC]
    ]
  end
end
