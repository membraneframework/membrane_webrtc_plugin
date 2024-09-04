# This example receives audio and video from obs via WHIP
# and saves it to a `recording.mkv` file.

require Logger
Logger.configure(level: :info)

Mix.install([
  {:membrane_webrtc_plugin, path: "#{__DIR__}/.."},
  :membrane_file_plugin,
  :membrane_realtimer_plugin,
  :membrane_matroska_plugin,
  :membrane_opus_plugin,
  :membrane_h264_plugin,
  :corsica
])

defmodule Example.Pipeline do
  use Membrane.Pipeline

  alias Membrane.WebRTC

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      [
        child(:webrtc, %WebRTC.Source{
          whip: "http://127.0.0.1:8829/whip"
        }),
        child(:matroska, Membrane.Matroska.Muxer),
        get_child(:webrtc)
        |> via_out(:output, options: [kind: :audio])
        |> child(Membrane.Opus.Parser)
        |> get_child(:matroska),
        get_child(:webrtc)
        |> via_out(:output, options: [kind: :video])
        |> get_child(:matroska),
        get_child(:matroska)
        |> child(:sink, %Membrane.File.Sink{location: "whip_recording.mkv"})
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
end

{:ok, supervisor, _pipeline} = Membrane.Pipeline.start_link(Example.Pipeline, port: 8829)
Process.monitor(supervisor)

receive do
  {:DOWN, _ref, :process, ^supervisor, _reason} -> :ok
end
