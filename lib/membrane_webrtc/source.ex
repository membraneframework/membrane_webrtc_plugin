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
  alias Membrane.WebRTC.ExWebRTCSourceWHIP
  use Membrane.Bin

  alias Membrane.WebRTC.{ExWebRTCSource, ExWebRTCUtils, SignalingChannel, SimpleWebSocketServer}

  @typedoc """
  Notification sent when new tracks arrive.

  See moduledoc for details.
  """
  @type new_tracks :: {:new_tracks, [%{id: term, kind: :audio | :video}]}

  def_options whip: [
                spec: String,
                description: """
                URL on which source will receive WebRTC WHIP stream
                """,
                default: nil
              ],
              signaling: [
                spec: SignalingChannel.t() | {:websocket, SimpleWebSocketServer.options()},
                description: """
                Channel for passing WebRTC signaling messages (SDP and ICE).
                Either:
                - `#{inspect(SignalingChannel)}` - See its docs for details.
                - `{:websocket, options}` - Spawns #{inspect(SimpleWebSocketServer)},
                see there for details.
                """,
                default: nil
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
  def handle_init(_ctx, %{whip: url} = opts) when url != nil do
    IO.inspect(url, label: "whip url")
    # return setup incomplete and run REST server that will wait for /whip request
    # return setup complete when client connects with a stream

    spec =
      child(:webrtc, %ExWebRTCSourceWHIP{
        whip: opts.whip,
        video_codec: opts.video_codec,
        ice_servers: opts.ice_servers
      })

    state = %{tracks: %{}, mode: :whip} |> Map.merge(opts)
    {[spec: spec], state}
  end

  def handle_init(_ctx, opts) do
    IO.inspect(opts, label: "opts")

    {signaling, opts} = opts |> Map.from_struct() |> Map.pop!(:signaling)

    spec =
      child(:webrtc, %ExWebRTCSource{
        signaling: signaling,
        video_codec: opts.video_codec,
        ice_servers: opts.ice_servers
      })

    state = %{tracks: %{}, mode: :signaling} |> Map.merge(opts)
    {[spec: spec], state}
  end

  @impl true
  def handle_setup(_ctx, %{mode: :whip} = state) do
    {[setup: :incomplete], state}
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
      |> then(if state.depayload_rtp, do: &child(&1, get_depayloader(kind, state)), else: & &1)
      |> bin_output(pad_ref)

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:new_tracks, tracks}, :webrtc, _ctx, state) do
    tracks_map = Map.new(tracks, &{&1.id, &1})
    state = %{state | tracks: Map.merge(state.tracks, tracks_map)}
    {[notify_parent: {:new_tracks, tracks}], state}
  end

  defp get_depayloader(:audio, _state) do
    %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.Opus.Depayloader,
      clock_rate: ExWebRTCUtils.codec_clock_rate(:opus)
    }
  end

  defp get_depayloader(:video, %{video_codec: :vp8}) do
    %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.VP8.Depayloader,
      clock_rate: ExWebRTCUtils.codec_clock_rate(:vp8)
    }
  end

  defp get_depayloader(:video, %{video_codec: :h264}) do
    %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.H264.Depayloader,
      clock_rate: ExWebRTCUtils.codec_clock_rate(:h264)
    }
  end
end
