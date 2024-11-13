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

  @typedoc """
  Options for WHIP server input.

  The server accepts a single connection and the stream is received by this source. The options are:

  - `token` - either expected WHIP token or a function returning true if the token is valid, otherwise false
  - `serve_static` - make WHIP server also serve static content, such as an HTML page under `/static` endpoint
  - Any of `t:Bandit.options/0` - in particular `ip` and `port`

  To handle multiple connections and have more control over the server, see `Membrane.WebRTC.WhipServer`.
  """
  @type whip_options :: [
          {:token, String.t() | (String.t() -> boolean())}
          | {:serve_static, String.t()}
          | {atom, term()}
        ]

  def_options signaling: [
                spec:
                  SignalingChannel.t()
                  | {:whip, whip_options()}
                  | {:websocket, SimpleWebSocketServer.options()},
                description: """
                Channel for passing WebRTC signaling messages (SDP and ICE).
                Either:
                - `#{inspect(SignalingChannel)}` - See its docs for details.
                - `{:whip, options}` - Starts a WHIP server, see `t:whip_options/0` for details.
                - `{:websocket, options}` - Spawns #{inspect(SimpleWebSocketServer)},
                see there for details.
                """
              ],
              allowed_video_codecs: [
                spec: :vp8 | :h264 | [:vp8 | :h264],
                default: :vp8,
                description: """
                Specifies, which video codecs can be accepted by the source during the SDP
                negotiaion.

                Either `:vp8`, `:h264` or a list containing both options.

                Event if it is set to `[:h264, :vp8]`, the source will negotiate at most
                one video codec. Negotiated codec can be deduced from
                `{:negotiated_video_codecs, codecs}` notification sent to the parent.

                If prefer to receive one video codec over another, but you are still able
                to handle both of them, use `:preferred_video_codec` option.

                By default only `:vp8`.
                """
              ],
              preferred_video_codec: [
                spec: :vp8 | :h264,
                default: :vp8,
                description: """
                Specyfies, which video codec will be preferred by the source, if both of
                them will be available.

                Usage of this option makes sense only if there are at least 2 codecs
                specified in the `:allowed_video_codecs` option.

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
              ],
              sdp_candidates_timeout: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.seconds(1),
                default_inspector: &Membrane.Time.pretty_duration/1
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

    :ok = Membrane.WebRTC.Utils.validate_signaling!(opts.signaling)

    state =
      %{tracks: %{}, negotiated_video_codecs: nil, awaiting_pads: MapSet.new()}
      |> Map.merge(opts)

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

    link_webrtc(pad_ref, kind || track.kind, state)
  end

  defp link_webrtc(pad_ref, kind, state) do
    spec =
      get_child(:webrtc)
      |> via_out(pad_ref, options: [kind: kind])

    spec =
      cond do
        not state.depayload_rtp ->
          spec |> bin_output(pad_ref)

        kind == :audio ->
          spec |> get_depayloader(:audio, state) |> bin_output(pad_ref)

        kind == :video and state.negotiated_video_codecs == nil ->
          [
            spec
            |> child({:forwarding_filter_a, pad_ref}, Membrane.WebRTC.Sink.ForwardingFilter),
            child({:forwarding_filter_b, pad_ref}, Membrane.WebRTC.Sink.ForwardingFilter)
            |> bin_output(pad_ref)
          ]

        kind == :video ->
          spec |> get_depayloader(:video, state) |> bin_output(pad_ref)
      end

    state =
      if kind == :video and state.negotiated_video_codecs == nil,
        do: state |> Map.update!(:awaiting_pads, &MapSet.put(&1, pad_ref)),
        else: state

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

    spec =
      state.awaiting_pads
      |> Enum.map(fn pad_ref ->
        get_child({:forwarding_filter_a, pad_ref})
        |> get_depayloader(:video, state)
        |> get_child({:forwarding_filter_b, pad_ref})
      end)

    state = %{state | awaiting_pads: MapSet.new()}

    {[notify_parent: {:negotiated_video_codecs, codecs}, spec: spec], state}
  end

  @impl true
  def handle_child_notification(_notification, {ff, _ref}, _ctx, state)
      when ff in [:forwarding_filter_a, :forwarding_filter_b] do
    {[], state}
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
