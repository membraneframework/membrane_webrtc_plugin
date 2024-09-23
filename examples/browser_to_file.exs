# This example receives audio and video from a browser via WebRTC
# and saves it to a `recording.mkv` file.
# To run it, type `elixir browser_to_file.exs` and open
# http://localhost:8000/index.html in your browser. To finish recording,
# click the `disconnect` button or close the tab.

require Logger
Logger.configure(level: :info)

Mix.install([
  {:membrane_webrtc_plugin, path: "#{__DIR__}/.."},
  :membrane_file_plugin,
  :membrane_realtimer_plugin,
  :membrane_matroska_plugin,
  :membrane_opus_plugin,
  :membrane_h264_plugin
])

defmodule Example.Pipeline do
  use Membrane.Pipeline

  alias Membrane.WebRTC

  @impl true
  def handle_init(_ctx, opts) do
    # p = self()

    # Membrane.WebRTC.WhipServer.start_link(
    #   port: 8888,
    #   handle_new_client: fn signaling, _token ->
    #     send(p, {:ready, signaling})
    #     :ok
    #   end
    # )

    # signaling = receive do: ({:ready, signaling} -> signaling)

    spec =
      [
        child(:webrtc, %WebRTC.Source{
          signaling: {:whip, port: 8888},
          video_codec: :h264
        }),
        child(:matroska, Membrane.Matroska.Muxer),
        get_child(:webrtc)
        |> via_out(:output, options: [kind: :audio])
        |> child(Membrane.Opus.Parser)
        |> get_child(:matroska),
        get_child(:webrtc)
        |> via_out(:output, options: [kind: :video])
        |> child(%Membrane.H264.Parser{output_stream_structure: :avc3})
        |> get_child(:matroska),
        get_child(:matroska)
        |> child(:sink, %Membrane.File.Sink{location: "recording.mkv"})
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

:ok = :inets.start()

{:ok, _server} =
  :inets.start(:httpd,
    bind_address: ~c"localhost",
    port: 8000,
    document_root: ~c"#{__DIR__}/assets/browser_to_file",
    server_name: ~c"webrtc",
    server_root: "/tmp"
  )

Logger.info("""
Visit http://localhost:8000/index.html to start the stream. To finish the recording properly,
don't terminate this script - instead click 'disconnect' in the website or close the browser tab.
""")

receive do
  {:DOWN, _ref, :process, ^supervisor, _reason} -> :ok
end
