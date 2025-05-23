defmodule Membrane.WebRTC.ExWebRTCSink do
  @moduledoc false

  use Membrane.Sink

  require Membrane.Logger

  alias ExWebRTC.{
    ICECandidate,
    MediaStreamTrack,
    PeerConnection,
    SessionDescription
  }

  alias ExRTCP.Packet.PayloadFeedback.PLI

  alias Membrane.WebRTC.{ExWebRTCUtils, Signaling, SimpleWebSocketServer}

  def_options signaling: [],
              tracks: [],
              video_codec: [],
              ice_servers: [],
              ice_port_range: [],
              ice_ip_filter: []

  def_input_pad :input,
    accepted_format: Membrane.RTP,
    availability: :on_request,
    options: [kind: [], codec: [default: nil]]

  @max_rtp_timestamp 2 ** 32 - 1
  @max_rtp_seq_num 2 ** 16 - 1
  @keyframe_request_throttle_time Membrane.Time.milliseconds(500)

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %{
       pc: nil,
       input_tracks: %{},
       queued_tracks: Enum.map(opts.tracks, &%{kind: &1, notify: false}),
       negotiating_tracks: [],
       negotiated_tracks: [],
       signaling: opts.signaling,
       status: :init,
       audio_params: ExWebRTCUtils.codec_params(:opus),
       video_params: ExWebRTCUtils.codec_params(opts.video_codec),
       video_codec: opts.video_codec,
       ice_servers: opts.ice_servers,
       ice_port_range: opts.ice_port_range,
       ice_ip_filter: opts.ice_ip_filter
     }}
  end

  @impl true
  def handle_setup(ctx, state) do
    signaling =
      case state.signaling do
        {:websocket, opts} ->
          SimpleWebSocketServer.start_link_supervised(ctx.utility_supervisor, opts)

        {:whip, opts} ->
          signaling = Signaling.new()

          Membrane.UtilitySupervisor.start_link_child(
            ctx.utility_supervisor,
            {Membrane.WebRTC.WhipClient, [signaling: signaling] ++ opts}
          )

          signaling

        signaling ->
          signaling
      end

    {:ok, pc} =
      PeerConnection.start_link(
        ice_servers: state.ice_servers,
        ice_port_range: state.ice_port_range,
        ice_ip_filter: state.ice_ip_filter,
        video_codecs: state.video_params,
        audio_codecs: state.audio_params
      )

    Process.monitor(signaling.pid)
    Signaling.register_element(signaling)
    state = %{state | pc: pc, status: :connecting, signaling: signaling}
    state = maybe_negotiate_tracks(state)
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, id) = pad, ctx, state) do
    %{kind: kind} = ctx.pad_options
    %{negotiated_tracks: negotiated_tracks, input_tracks: input_tracks} = state

    track =
      if kind do
        Enum.find(negotiated_tracks, &(&1.kind == kind))
      else
        Enum.find(negotiated_tracks, &(&1.id == id))
      end

    unless track do
      raise "Couldn't associate track with the pad of id #{inspect(id)} and kind #{inspect(kind)}"
    end

    negotiated_tracks = List.delete(negotiated_tracks, track)

    params = %{
      kind: track.kind,
      clock_rate:
        case track.kind do
          :audio -> ExWebRTCUtils.codec_clock_rate(:opus)
          :video -> ExWebRTCUtils.codec_clock_rate(state.video_codec)
        end,
      seq_num: Enum.random(0..@max_rtp_seq_num),
      last_keyframe_request_ts: Membrane.Time.monotonic_time() - @keyframe_request_throttle_time
    }

    input_tracks = Map.put(input_tracks, pad, {track.id, params})
    state = %{state | negotiated_tracks: negotiated_tracks, input_tracks: input_tracks}
    {[], state}
  end

  @impl true
  def handle_start_of_stream(pad, ctx, state) do
    case ctx.pads[pad].options do
      %{kind: :audio} ->
        :ok

      %{kind: :video, codec: nil} ->
        supported_video_codecs = get_transceiver(state, pad)

        if length(supported_video_codecs) > 1 do
          raise """
          Cannot determine the video codec of the stream. It's necessary, as multiple video codecs \
          have been negotiated. This error might be caused by passing `Membrane.RTP` to \
          `Membrane.WebRTC.Sink` and allowing to negotiate more than one video codec at the same \
          time.
          Negotiated video codecs: #{inspect(supported_video_codecs, pretty: true)}
          """
        end

        :ok

      %{kind: :video, codec: codec} ->
        :ok = set_pc_sender_video_codec(state, pad, codec)
    end

    {[], state}
  end

  defp set_pc_sender_video_codec(state, pad, codec) when codec in [:vp8, :h264] do
    mime_type = if codec == :vp8, do: "video/VP8", else: "video/H264"
    transceiver = get_transceiver(state, pad)

    if transceiver == nil do
      raise """
      Pad with `kind: :video` was linked, but #{inspect(PeerConnection)} doesn't have any video \
      transceiver.
      """
    end

    selected_codec =
      transceiver.codecs
      |> Enum.find(&(&1.mime_type == mime_type))

    if selected_codec == nil do
      raise """
      Cannot select codec #{inspect(codec)} with video transceiver #{inspect(transceiver)}
      """
    end

    :ok = PeerConnection.set_sender_codec(state.pc, transceiver.sender.id, selected_codec)
  end

  defp get_transceiver(state, pad) do
    {track_id, _params} = state.input_tracks[pad]

    state.pc
    |> PeerConnection.get_transceivers()
    |> Enum.find(&(&1.sender.track.id == track_id))
  end

  @impl true
  def handle_buffer(pad, buffer, _ctx, state) do
    state = send_buffer(pad, buffer, state)
    {[], state}
  end

  @impl true
  def handle_parent_notification({:add_tracks, kinds}, _ctx, state) do
    Membrane.Logger.debug("Adding tracks #{inspect(kinds)}")
    tracks = Enum.map(kinds, &%{kind: &1, notify: true})
    state = %{state | queued_tracks: state.queued_tracks ++ tracks}
    state = maybe_negotiate_tracks(state)
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, _msg}, _ctx, %{status: :closed} = state) do
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:ice_candidate, candidate}}, _ctx, state) do
    Signaling.signal(state.signaling, candidate)
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:connection_state_change, :connected}}, _ctx, state) do
    Membrane.Logger.debug("webrtc connected")
    {[setup: :complete, notify_parent: :connected], %{state | status: :connected}}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {message, track_id}}, _ctx, _state)
      when message in [:track_muted, :track_removed] do
    raise "Track #{inspect(track_id)} was rejected by the other peer"
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:rtcp, rtcp_packets}}, _ctx, state) do
    time = Membrane.Time.monotonic_time()

    {keyframe_requests, input_tracks} =
      rtcp_packets
      |> Enum.filter(fn
        {_track_id, %PLI{} = packet} ->
          Membrane.Logger.debug("Keyframe request received: #{inspect(packet)}")
          true

        packet ->
          Membrane.Logger.debug_verbose("Ignoring RTCP packet: #{inspect(packet)}")
          false
      end)
      |> Enum.flat_map_reduce(state.input_tracks, fn {track_id, _pli}, input_tracks ->
        {pad, {_id, props}} =
          Enum.find(input_tracks, fn {_pad, {id, _props}} -> track_id == id end)

        if props.kind == :video and
             time - props.last_keyframe_request_ts > @keyframe_request_throttle_time do
          event = [event: {pad, %Membrane.KeyframeRequestEvent{}}]
          props = %{props | last_keyframe_request_ts: time}
          {event, %{input_tracks | pad => {track_id, props}}}
        else
          {[], input_tracks}
        end
      end)

    {keyframe_requests, %{state | input_tracks: input_tracks}}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, message}, _ctx, state) do
    Membrane.Logger.debug("Ignoring ex_webrtc message: #{inspect(message)}")
    {[], state}
  end

  @impl true
  def handle_info(
        {:membrane_webrtc_signaling, _pid, %SessionDescription{type: :offer}, _metadata},
        _ctx,
        _state
      ) do
    raise "WebRTC sink received SDP offer, while it sends offer and expects an answer"
  end

  @impl true
  def handle_info(
        {:membrane_webrtc_signaling, _pid, %SessionDescription{type: :answer} = sdp, _metadata},
        _ctx,
        state
      ) do
    Membrane.Logger.debug("Received SDP answer")
    :ok = PeerConnection.set_remote_description(state.pc, sdp)

    %{negotiating_tracks: negotiating_tracks, negotiated_tracks: negotiated_tracks} = state

    video_codecs = ExWebRTCUtils.get_video_codecs_from_sdp(sdp)

    to_notify =
      negotiating_tracks |> Enum.filter(& &1.notify) |> Enum.map(&Map.take(&1, [:id, :kind]))

    new_tracks_notification =
      if to_notify == [], do: [], else: [notify_parent: {:new_tracks, to_notify}]

    actions = [notify_parent: {:negotiated_video_codecs, video_codecs}] ++ new_tracks_notification

    negotiated_tracks = negotiated_tracks ++ negotiating_tracks

    state =
      %{state | negotiated_tracks: negotiated_tracks, negotiating_tracks: []}
      |> maybe_negotiate_tracks()

    {actions, state}
  end

  @impl true
  def handle_info(
        {:membrane_webrtc_signaling, _pid, %ICECandidate{} = candidate, _metadata},
        _ctx,
        state
      ) do
    :ok = PeerConnection.add_ice_candidate(state.pc, candidate)
    {[], state}
  end

  @impl true
  def handle_info(
        {:DOWN, _monitor, :process, signaling_pid, _reason},
        _ctx,
        %{signaling: %{pid: signaling_pid}} = state
      ) do
    {[], %{state | status: :closed}}
  end

  defp maybe_negotiate_tracks(%{negotiating_tracks: negotiating_tracks} = state)
       when negotiating_tracks != [] do
    state
  end

  defp maybe_negotiate_tracks(%{queued_tracks: []} = state) do
    state
  end

  defp maybe_negotiate_tracks(%{queued_tracks: queued_tracks, pc: pc} = state) do
    negotiating_tracks =
      Enum.map(queued_tracks, fn track ->
        webrtc_track = MediaStreamTrack.new(track.kind)
        PeerConnection.add_track(pc, webrtc_track)
        Map.put(track, :id, webrtc_track.id)
      end)

    PeerConnection.get_transceivers(pc)
    |> Enum.filter(&(&1.direction == :sendrecv))
    |> Enum.each(&PeerConnection.set_transceiver_direction(pc, &1.id, :sendonly))

    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)
    Signaling.signal(state.signaling, offer)
    %{state | negotiating_tracks: negotiating_tracks, queued_tracks: []}
  end

  defp send_buffer(pad, buffer, state) do
    {id, params} = state.input_tracks[pad]

    timestamp =
      Membrane.Time.divide_by_timebase(
        buffer.pts,
        Ratio.new(Membrane.Time.second(), params.clock_rate)
      )
      |> rem(@max_rtp_timestamp + 1)

    packet =
      ExRTP.Packet.new(buffer.payload,
        timestamp: timestamp,
        marker: buffer.metadata[:rtp][:marker] || false,
        sequence_number: params.seq_num
      )

    PeerConnection.send_rtp(state.pc, id, packet)
    seq_num = rem(params.seq_num + 1, @max_rtp_seq_num + 1)
    put_in(state.input_tracks[pad], {id, %{params | seq_num: seq_num}})
  end
end
