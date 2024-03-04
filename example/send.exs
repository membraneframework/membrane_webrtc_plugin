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
        child(:webrtc, %WebRTC.Sink{signaling_channel: {:websocket, port: opts[:port]}, tracks: [:audio, :video]}),
        child(%Membrane.File.Source{location: "bbb.h264"})
        |> child(%Membrane.H264.Parser{
          generate_best_effort_timestamps: %{framerate: {30, 1}},
          output_alignment: :nalu
        })
        |> child(Membrane.Realtimer)
        |> via_in(:input, options: [kind: :video])
        |> get_child(:webrtc)
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
