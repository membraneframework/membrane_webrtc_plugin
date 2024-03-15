# Logger.configure(level: :info)

Mix.install([
  {:membrane_webrtc_plugin, path: "."},
  :membrane_file_plugin,
  :membrane_realtimer_plugin,
  {:membrane_matroska_plugin, path: "../membrane_matroska_plugin"},
  :membrane_opus_plugin,
  :membrane_h26x_plugin
])

defmodule Example.Pipeline do
  use Membrane.Pipeline

  alias Membrane.WebRTC

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      child(%Membrane.File.Source{location: "bbb_h264_big.mkv"})
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
        child(:webrtc, %WebRTC.Sink{
          signaling: {:websocket, port: state.port},
          video_codec: :h264
        }),
        get_child(:demuxer)
        |> via_out(Pad.ref(:output, state.video_track))
        |> child(%Membrane.H264.Parser{
          output_stream_structure: :annexb,
          output_alignment: :nalu
        })
        |> child({:realtimer, :video_track}, Membrane.Realtimer)
        |> via_in(:input, options: [kind: :video])
        |> get_child(:webrtc),
        get_child(:demuxer)
        |> via_out(Pad.ref(:output, state.audio_track))
        |> child({:realtimer, :audio_track}, Membrane.Realtimer)
        |> via_in(:input, options: [kind: :audio])
        |> get_child(:webrtc)
      ]

      {[spec: spec], state}
    else
      {[], state}
    end
  end

  @impl true
  def handle_element_end_of_stream({:realtimer, track}, :input, _ctx, state) do
    state = %{state | track => nil}

    if !state.audio_track && !state.video_track do
      {[terminate: :normal], state}
    else
      {[], state}
    end
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
