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

  alias Membrane.WebRTC.{ExWebRTCSink, SignalingChannel}

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

  @type ws_opts :: %{ip: :inet.ip_address(), port: :inet.port_number()}

  def_options signaling: [
                spec: SignalingChannel.t() | {:websocket, ws_opts},
                description: """
                Channel for passing WebRTC signaling messages (SDP and ICE).
                Either:
                - `#{inspect(SignalingChannel)}` - See its docs for details.
                - `{:websocket, options}` - A simple WebSocket server
                that will accept a single connection. Each message sent through
                the socket should be a JSON-encoded
                `t:#{inspect(SignalingChannel)}.json_data_message/0`.
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
                spec: :vp8 | :h264,
                default: :vp8
              ],
              ice_servers: [
                spec: [ExWebRTC.PeerConnection.Configuration.ice_server()],
                default: [%{urls: "stun:stun.l.google.com:19302"}]
              ],
              payload_rtp: [
                spec: boolean(),
                default: true
              ]

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request

  def_input_pad :input,
    accepted_format: _any,
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
  def handle_pad_added(Pad.ref(:input, _pid) = pad_ref, ctx, state) do
    %{kind: kind} = ctx.pad_options

    spec =
      if state.payload_rtp do
        bin_input(pad_ref)
        |> child(get_payloader(kind, state))
        |> via_in(pad_ref, options: [kind: kind])
        |> get_child(:webrtc)
      else
        bin_input(pad_ref)
        |> via_in(pad_ref, options: [kind: kind])
        |> get_child(:webrtc)
      end

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(:connected, :webrtc, _ctx, state) do
    {[setup: :complete], state}
  end

  @impl true
  def handle_child_notification({:new_tracks, tracks}, :webrtc, _ctx, state) do
    {[notify_parent: {:new_tracks, tracks}], state}
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

  defp get_payloader(:audio, _state), do: Membrane.RTP.Opus.Payloader

  defp get_payloader(:video, %{video_codec: :h264}),
    do: %Membrane.RTP.H264.Payloader{max_payload_size: 1000}

  defp get_payloader(:video, %{video_codec: :vp8}), do: Membrane.RTP.VP8.Payloader
end
