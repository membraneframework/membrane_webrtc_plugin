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

  alias Membrane.WebRTC.{ExWebRTCSource, SignalingChannel}

  @typedoc """
  Notification sent when new tracks arrive.

  See moduledoc for details.
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
              video_codec: [
                spec: :vp8 | :h264,
                default: :vp8
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
    accepted_format: _any,
    availability: :on_request,
    options: [kind: [default: nil]]

  @impl true
  def handle_init(_ctx, opts) do
    {signaling, opts} = opts |> Map.from_struct() |> Map.pop!(:signaling)

    spec =
      child(:webrtc, %ExWebRTCSource{
        signaling: signaling,
        video_codec: opts.video_codec,
        ice_servers: opts.ice_servers
      })

    state = %{tracks: %{}} |> Map.merge(opts)
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
      if state.depayload_rtp do
        get_child(:webrtc)
        |> via_out(pad_ref, options: [kind: kind])
        |> child(get_depayloader(kind, state))
        |> bin_output(pad_ref)
      else
        get_child(:webrtc) |> via_out(pad_ref) |> bin_output(pad_ref)
      end

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:new_tracks, tracks}, :webrtc, _ctx, state) do
    tracks_map = Map.new(tracks, &{&1.id, &1})
    state = %{state | tracks: Map.merge(state.tracks, tracks_map)}
    {[notify_parent: {:new_tracks, tracks}], state}
  end

  defp get_depayloader(:audio, _state) do
    %Membrane.RTP.DepayloaderBin{depayloader: Membrane.RTP.Opus.Depayloader, clock_rate: 48_000}
  end

  defp get_depayloader(:video, %{video_codec: :vp8}) do
    %Membrane.RTP.DepayloaderBin{depayloader: Membrane.RTP.VP8.Depayloader, clock_rate: 96_000}
  end

  defp get_depayloader(:video, %{video_codec: :h264}) do
    %Membrane.RTP.DepayloaderBin{depayloader: Membrane.RTP.H264.Depayloader, clock_rate: 96_000}
  end
end
