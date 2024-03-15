defmodule Membrane.WebRTC.ExWebRTCSink do
  use Membrane.Sink

  require Membrane.Logger

  alias ExWebRTC.{
    ICECandidate,
    MediaStreamTrack,
    PeerConnection,
    SessionDescription
  }

  alias Membrane.WebRTC.{SignalingChannel, SimpleWebSocketServer, Utils}

  def_options signaling: [], tracks: [], video_codec: []

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request,
    options: [kind: []]

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %{
       pc: nil,
       input_tracks: %{},
       awaiting_tracks: Enum.map(opts.tracks, &%{kind: &1, id: nil}),
       signaling: opts.signaling,
       status: :init,
       audio_params: Utils.codec_params(:opus),
       video_params: Utils.codec_params(opts.video_codec),
       ice_servers: Utils.ice_servers()
     }}
  end

  @impl true
  def handle_setup(ctx, state) do
    case state.signaling do
      %SignalingChannel{} ->
        state = start_pc(state)
        {[setup: :incomplete], state}

      {:websocket, opts} ->
        Membrane.UtilitySupervisor.start_link_child(
          ctx.utility_supervisor,
          {SimpleWebSocketServer, [element: self()] ++ opts}
        )

        {[setup: :incomplete], state}
    end
  end

  @impl true
  def handle_pad_added(pad, %{playback: :stopped} = ctx, state) do
    %{kind: kind} = ctx.pad_options
    %{awaiting_tracks: awaiting_tracks, input_tracks: input_tracks} = state
    track = Enum.find(awaiting_tracks, &(&1.kind == kind))
    awaiting_tracks = List.delete(awaiting_tracks, track)

    params =
      case track.kind do
        :audio -> state.audio_params
        :video -> state.video_params
      end

    input_tracks = Map.put(input_tracks, pad, {track.id, params})
    state = %{state | awaiting_tracks: awaiting_tracks, input_tracks: input_tracks}
    {[], state}
  end

  @impl true
  def handle_buffer(pad, buffer, _ctx, state) do
    send_buffer(pad, buffer, state)
    {[], state}
  end

  @impl true
  def handle_info({:signaling, signaling}, _ctx, state) do
    state = start_pc(%{state | signaling: signaling})
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, _msg}, _ctx, %{status: :closed} = state) do
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:ice_candidate, candidate}}, _ctx, state) do
    send(state.signaling.pid, {:element, candidate})
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:connection_state_change, :connected}}, _ctx, state) do
    Membrane.Logger.info("connected")
    {[setup: :complete, notify_parent: :connected], %{state | status: :connected}}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, message}, _ctx, state) do
    Membrane.Logger.warning("Unexpected message: #{inspect(message)}")
    {[], state}
  end

  @impl true
  def handle_info({SignalingChannel, _pid, %SessionDescription{type: :answer} = sdp}, _ctx, state) do
    :ok = PeerConnection.set_remote_description(state.pc, sdp)
    {[], state}
  end

  @impl true
  def handle_info({SignalingChannel, _pid, %ICECandidate{} = candidate}, _ctx, state) do
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

  defp start_pc(state) do
    {:ok, pc} =
      PeerConnection.start_link(
        ice_servers: state.ice_servers,
        video_codecs: [state.video_params],
        audio_codecs: [state.audio_params]
      )

    Process.monitor(state.signaling.pid)
    send(state.signaling.pid, {:register_element, self()})

    awaiting_tracks =
      Enum.map(state.awaiting_tracks, fn %{kind: kind} = track ->
        webrtc_track = MediaStreamTrack.new(kind)
        PeerConnection.add_track(pc, webrtc_track)
        %{track | id: webrtc_track.id}
      end)

    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)
    send(state.signaling.pid, {:element, offer})

    %{state | awaiting_tracks: awaiting_tracks, pc: pc, status: :connecting}
  end

  defp send_buffer(pad, buffer, state) do
    {id, params} = state.input_tracks[pad]

    timestamp =
      Membrane.Time.divide_by_timebase(
        buffer.pts,
        Ratio.new(Membrane.Time.second(), params.clock_rate)
      )

    packet =
      ExRTP.Packet.new(buffer.payload,
        payload_type: params.payload_type,
        timestamp: timestamp,
        marker: buffer.metadata[:rtp][:marker] || false
      )

    PeerConnection.send_rtp(state.pc, id, packet)
  end
end
