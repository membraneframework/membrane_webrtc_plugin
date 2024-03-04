Mix.install([
  {:membrane_webrtc_plugin, path: "."},
  :membrane_file_plugin,
  :membrane_realtimer_plugin,
  {:membrane_matroska_plugin, path: "../membrane_matroska_plugin"},
  :membrane_opus_plugin,
  :membrane_h264_plugin,
  {:plug, "~> 1.15.0"},
  {:bandit, "~> 1.2.0"},
  {:websock_adapter, "~> 0.5.0"},
  {:jason, "~> 1.4.0"}
])

defmodule Example.Pipeline do
  use Membrane.Pipeline

  alias Membrane.WebRTC

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      [
        child(:webrtc, %WebRTC.Source{signaling_channel: {:websocket, port: opts[:port]}}),
        child(:matroska, Membrane.Matroska.Muxer)
        |> child(:sink, %Membrane.File.Sink{location: "recording.mkv"}),
        get_child(:webrtc)
        |> via_out(Pad.ref(:output, :audio))
        |> child(Membrane.Opus.Parser)
        |> get_child(:matroska),
        get_child(:webrtc)
        |> via_out(Pad.ref(:output, :video))
        |> child(%Membrane.H264.Parser{output_stream_structure: :avc3})
        |> get_child(:matroska)
      ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_element_end_of_stream(:sink, :input, _ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    {[], state}
  end
end

Logger.configure(level: :debug)

Membrane.Pipeline.start_link(Example.Pipeline, port: 8829)

Process.sleep(:infinity)
