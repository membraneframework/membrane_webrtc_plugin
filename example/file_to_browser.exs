Logger.configure(level: :info)

Mix.install([
  {:membrane_webrtc_plugin, path: "."},
  :membrane_file_plugin,
  :membrane_realtimer_plugin,
  :membrane_matroska_plugin,
  :membrane_opus_plugin
])

defmodule Example.Pipeline do
  use Membrane.Pipeline

  alias Membrane.WebRTC

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      child(%Membrane.File.Source{location: "bbb_vp8.mkv"})
      |> child(:demuxer, Membrane.Matroska.Demuxer)

    {[spec: spec], %{audio_track: nil, video_track: nil, port: opts[:port]}}
  end

  @impl true
  def handle_child_notification({:new_track, {id, info}}, :demuxer, _ctx, state) do
    state =
      case info.codec do
        :opus -> %{state | audio_track: id}
        :h264 -> %{state | video_track: id}
        :vp8 -> %{state | video_track: id}
      end

    if state.audio_track && state.video_track do
      spec = [
        child(:webrtc, %WebRTC.Sink{signaling: {:websocket, port: state.port}}),
        get_child(:demuxer)
        |> via_out(Pad.ref(:output, state.video_track))
        |> child({:realtimer, :video_track}, Membrane.Realtimer)
        |> via_in(Pad.ref(:input, :video_track), options: [kind: :video])
        |> get_child(:webrtc),
        get_child(:demuxer)
        |> via_out(Pad.ref(:output, state.audio_track))
        |> child({:realtimer, :audio_track}, Membrane.Realtimer)
        |> via_in(Pad.ref(:input, :audio_track), options: [kind: :audio])
        |> get_child(:webrtc)
      ]

      {[spec: spec], state}
    else
      {[], state}
    end
  end

  @impl true
  def handle_child_notification({:end_of_stream, track}, :webrtc, _ctx, state) do
    state = %{state | track => nil}

    if !state.audio_track && !state.video_track do
      {[terminate: :normal], state}
    else
      {[], state}
    end
  end

  @impl true
  def handle_child_notification(_notification, _child, _ctx, state) do
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
    document_root: ~c"#{__DIR__}/assets/file_to_browser",
    server_name: ~c"webrtc",
    server_root: "/tmp"
  )

receive do
  {:DOWN, _ref, :process, ^supervisor, _reason} -> :ok
end
