defmodule Membrane.WebRTC.Sink do
  @moduledoc """
  Membrane Bin that allows sending audio and video tracks via WebRTC.

  It sends an SDP offer and expects an answer during initialization and
  each time when new tracks are added. For more information about signaling,
  see the `signaling` option.

  Before connecting pads, each audio and video track has to be negotiated.
  Tracks passed via `tracks` option are negotiated during initialization.
  You can negotiate more tracks by sending `t:add_tracks/0` notification
  and waiting for `t:new_tracks/0` notification reply.

  When the tracks are negotiated, pads can be linked. The pad either
  has to have a `kind` option set or its id has to match the id of
  the track received in `t:new_tracks/0` notification.
  """
  use Membrane.Bin

  alias Membrane.H264
  alias Membrane.RemoteStream
  alias Membrane.VP8
  alias Membrane.WebRTC.{ExWebRTCSink, ForwardingFilter, SignalingChannel, SimpleWebSocketServer}

  @typedoc """
  Notification that should be sent to the bin to negotiate new tracks.

  See the moduledoc for details.
  """
  @type add_tracks :: {:add_tracks, [:audio | :video]}

  @typedoc """
  Notification sent when new tracks are negotiated.

  See the moduledoc for details.
  """
  @type new_tracks :: {:new_tracks, [%{id: term, kind: :audio | :video}]}

  @typedoc """
  WHIP client options

  - `uri` - Address of the WHIP server (HTTP/HTTPS)
  - `token` - WHIP token, defaults to an empty string
  """
  @type whip_options :: [{:uri, String.t()} | {:token, String.t()}]

  def_options signaling: [
                spec:
                  SignalingChannel.t()
                  | {:whip, whip_options}
                  | {:websocket, SimpleWebSocketServer.options()},
                description: """
                Channel for passing WebRTC signaling messages (SDP and ICE).
                Either:
                - `#{inspect(SignalingChannel)}` - See its docs for details.
                - `{:whip, options}` - Acts as a WHIP client, see `t:whip_options/0` for details.
                - `{:websocket, options}` - Spawns #{inspect(SimpleWebSocketServer)},
                see there for details.
                """
              ],
              tracks: [
                spec: [:audio | :video],
                default: [:audio, :video],
                description: """
                Tracks to be negotiated. By default one audio and one video track
                is negotiated, meaning that at most one audio and one video can be
                sent.
                """
              ],
              video_codec: [
                spec: :vp8 | :h264 | [:vp8 | :h264],
                default: [:vp8, :h264],
                description: """
                Video codecs, that #{inspect(__MODULE__)} will try to negotiatie in SDP
                message exchange. Even if `[:vp8, :h264]` is passed to this option, there
                is a chance, that one of these codecs won't be approved by the second
                WebRTC peer.

                After SDP messages exchange, #{inspect(__MODULE__)} will send a parent
                notification `{:new_tracks, tracks}`, where every track in `tracks`
                contains info about supported codecs.
                """
              ],
              ice_servers: [
                spec: [ExWebRTC.PeerConnection.Configuration.ice_server()],
                default: [%{urls: "stun:stun.l.google.com:19302"}]
              ],
              payload_rtp: [
                spec: boolean(),
                default: true
              ]

  def_input_pad :input,
    accepted_format:
      any_of(
        %Membrane.H264{alignment: :nalu},
        %Membrane.RemoteStream{content_format: Membrane.VP8},
        Membrane.Opus,
        Membrane.RTP
      ),
    availability: :on_request,
    options: [
      kind: [
        spec: :audio | :video | nil,
        default: nil,
        description: """
        When set, the pad is associated with the first negotiated track
        of the given kind. See the moduledoc for details.
        """
      ]
    ]

  @impl true
  def handle_init(_ctx, opts) do
    :ok = Membrane.WebRTC.Utils.validate_signaling!(opts.signaling)

    spec =
      child(:webrtc, %ExWebRTCSink{
        signaling: opts.signaling,
        tracks: opts.tracks,
        video_codec: opts.video_codec,
        ice_servers: opts.ice_servers
      })

    {[spec: spec], %{tracks: %{}, payload_rtp: opts.payload_rtp, video_codec: opts.video_codec}}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, pid) = pad_ref, %{pad_options: %{kind: kind}}, state) do
    spec =
      cond do
        not state.payload_rtp ->
          bin_input(pad_ref)
          |> via_in(pad_ref, options: [kind: kind])
          |> get_child(:webrtc)

        kind == :audio ->
          bin_input(pad_ref)
          |> child({:rtp_opus_payloader, pid}, Membrane.RTP.Opus.Payloader)
          |> via_in(pad_ref, options: [kind: :audio])
          |> get_child(:webrtc)

        kind == :video ->
          bin_input(pad_ref)
          |> child({:forwarding_filter, pad_ref}, ForwardingFilter)
      end

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(
        {:stream_format, stream_format},
        {:forwarding_filter, pad_ref},
        _ctx,
        state
      ) do
    payoader =
      case stream_format do
        %H264{} -> %Membrane.RTP.H264.Payloader{max_payload_size: 1000}
        %VP8{} -> Membrane.RTP.VP8.Payloader
        %RemoteStream{content_format: VP8} -> Membrane.RTP.VP8.Payloader
      end

    spec =
      get_child({:forwarding_filter, pad_ref})
      |> child({:rtp_payloader, pad_ref}, payoader)
      |> via_in(pad_ref, options: [kind: :video])
      |> get_child(:webrtc)

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(:connected, :webrtc, _ctx, state) do
    {[setup: :complete], state}
  end

  @impl true
  def handle_child_notification({type, _content} = notification, :webrtc, _ctx, state)
      when type in [:new_tracks, :negotiated_video_codecs] do
    {[notify_parent: notification], state}
  end

  @impl true
  def handle_parent_notification({:add_tracks, tracks}, _ctx, state) do
    {[notify_child: {:webrtc, {:add_tracks, tracks}}], state}
  end

  @impl true
  def handle_element_end_of_stream(:webrtc, Pad.ref(:input, id), _ctx, state) do
    {[notify_parent: {:end_of_stream, id}], state}
  end

  @impl true
  def handle_element_end_of_stream(_name, _pad, _ctx, state) do
    {[], state}
  end
end
