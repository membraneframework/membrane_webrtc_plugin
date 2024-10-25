defmodule Membrane.WebRTC.Source do
  @moduledoc """
  Membrane Bin that allows receiving audio and video tracks via WebRTC.

  It expects an SDP offer to be sent by the other peer at the beginning
  of playback and each time new tracks are added. For more information
  about signaling, see the `signaling` option.

  Pads connected immediately when the bin is created
  (in the same spec `t:Membrane.ChildrenSpec.t/0`) need to have the `kind`
  option set to `:audio` or `:video`. Each of those pads will be associated
  with the first WebRTC track of the given kind that arrives.

  When a WebRTC tracks arrive and there's no pad to link them to,
  the `t:new_tracks/0` notification is sent. Then, the corresponding pads
  should be linked - the id of each pad should match one of the track ids.
  """
  use Membrane.Bin

  alias Membrane.WebRTC.{ExWebRTCSource, ExWebRTCUtils, SignalingChannel, SimpleWebSocketServer}

  @typedoc """
  Notification sent when new tracks arrive.

  See moduledoc for details.
  """
  @type new_tracks :: {:new_tracks, [%{id: term, kind: :audio | :video}]}

  def_options signaling: [
                spec: SignalingChannel.t() | {:websocket, SimpleWebSocketServer.options()},
                description: """
                Channel for passing WebRTC signaling messages (SDP and ICE).
                Either:
                - `#{inspect(SignalingChannel)}` - See its docs for details.
                - `{:websocket, options}` - Spawns #{inspect(SimpleWebSocketServer)},
                see there for details.
                """
              ],
              allowed_video_codecs: [
                spec: :vp8 | :h264 | [:vp8 | :h264],
                default: :vp8,
                description: """
                Specyfies, which video codecs can be accepted by source during the SDP
                negotiaion.

                Either `:vp8`, `:h264` or a list containing both options.

                Event if it is set to `[:h264, :vp8]`, the source will negotiate at most
                one video codec. Negotiated codec can be deduced from
                `{:negotiated_video_codecs, codecs}` notification sent to the parent.

                If prefer to receive one video codec over another, but you are still able
                to handle both of them, use `:suggested_video_codec` option.

                By default only `:vp8`.
                """
              ],
              suggested_video_codec: [
                spec: :vp8 | :h264,
                default: :vp8,
                description: """
                Specyfies, which video codec will be preferred by the source, if both of
                them will be available.

                Usage of this option makes sense only if option `:allowed_video_codecs`
                is set to `[:vp8, :h264]` or `[:h264, :vp8]`.

                Defaults to `:vp8`.
                """
              ],
              keyframe_interval: [
                spec: Membrane.Time.t() | nil,
                default: nil,
                description: """
                If set, a keyframe will be requested as often as specified on each video
                track.
                """
              ],
              ice_servers: [
                spec: [ExWebRTC.PeerConnection.Configuration.ice_server()],
                default: [%{urls: "stun:stun.l.google.com:19302"}]
              ],
              depayload_rtp: [
                spec: boolean(),
                default: true
              ]

  def_output_pad :output,
    accepted_format:
      any_of(
        Membrane.H264,
        %Membrane.RemoteStream{content_format: Membrane.VP8},
        %Membrane.RemoteStream{content_format: Membrane.Opus},
        Membrane.RTP
      ),
    availability: :on_request,
    options: [kind: [default: nil]]

  @impl true
  def handle_init(_ctx, opts) do
    opts = opts |> Map.from_struct() |> Map.update!(:allowed_video_codecs, &Bunch.listify/1)
    spec = child(:webrtc, struct(ExWebRTCSource, opts))

    state =
      %{tracks: %{}, negotiated_video_codecs: nil}
      |> Map.merge(opts)
      |> Map.delete(:signaling)

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, pad_id) = pad_ref, ctx, state) do
    %{kind: kind} = ctx.pad_options
    track = state.tracks[pad_id]

    if ctx.playback == :stopped and kind == nil do
      raise "Option `kind` not specified for pad #{inspect(pad_ref)}"
    end

    if ctx.playback == :playing and track == nil do
      raise "Unknown track id #{inspect(pad_id)}, cannot link pad #{inspect(pad_ref)}"
    end

    kind = kind || track.kind

    spec =
      get_child(:webrtc)
      |> via_out(pad_ref, options: [kind: kind])
      |> then(if state.depayload_rtp, do: &get_depayloader(&1, kind, state), else: & &1)
      |> bin_output(pad_ref)

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:new_tracks, tracks}, :webrtc, _ctx, state) do
    tracks_map = Map.new(tracks, &{&1.id, &1})
    state = %{state | tracks: Map.merge(state.tracks, tracks_map)}
    {[notify_parent: {:new_tracks, tracks}], state}
  end

  @impl true
  def handle_child_notification({:negotiated_video_codecs, codecs}, :webrtc, _ctx, state) do
    state = %{state | negotiated_video_codecs: codecs}
    {[notify_parent: {:negotiated_video_codecs, codecs}], state}
  end

  defp get_depayloader(builder, :audio, _state) do
    child(builder, %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.Opus.Depayloader,
      clock_rate: ExWebRTCUtils.codec_clock_rate(:opus)
    })
  end

  defp get_depayloader(builder, :video, state) do
    cond do
      state.allowed_video_codecs == [:vp8] ->
        get_vp8_depayloader(builder)

      state.allowed_video_codecs == [:h264] ->
        get_h264_depayloader(builder)

      state.negotiated_video_codecs == [:vp8] ->
        get_vp8_depayloader(builder)

      state.negotiated_video_codecs == [:h264] ->
        get_h264_depayloader(builder)

      state.negotiated_video_codecs == nil ->
        raise "Cannot select depayloader before end of SDP messages exchange"
    end
  end

  defp get_vp8_depayloader(builder) do
    child(builder, %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.VP8.Depayloader,
      clock_rate: ExWebRTCUtils.codec_clock_rate(:vp8)
    })
  end

  defp get_h264_depayloader(builder) do
    child(builder, %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.H264.Depayloader,
      clock_rate: ExWebRTCUtils.codec_clock_rate(:h264)
    })
  end
end
