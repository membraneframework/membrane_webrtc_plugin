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
       queued_tracks: Enum.map(opts.tracks, &%{kind: &1, notify: false}),
       negotiating_tracks: [],
       negotiated_tracks: [],
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

    params =
      case track.kind do
        :audio -> state.audio_params
        :video -> state.video_params
      end

    input_tracks = Map.put(input_tracks, pad, {track.id, params})
    state = %{state | negotiated_tracks: negotiated_tracks, input_tracks: input_tracks}
    {[], state}
  end

  @impl true
  def handle_buffer(pad, buffer, _ctx, state) do
    send_buffer(pad, buffer, state)
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
    Membrane.Logger.debug("webrtc connected")
    {[setup: :complete, notify_parent: :connected], %{state | status: :connected}}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, message}, _ctx, state) do
    Membrane.Logger.debug("Ignoring ex_webrtc message: #{inspect(message)}")
    {[], state}
  end

  @impl true
  def handle_info({SignalingChannel, _pid, %SessionDescription{type: :answer} = sdp}, _ctx, state) do
    :ok = PeerConnection.set_remote_description(state.pc, sdp)

    %{negotiating_tracks: negotiating_tracks, negotiated_tracks: negotiated_tracks} = state

    to_notify =
      negotiating_tracks |> Enum.filter(& &1.notify) |> Enum.map(&Map.take(&1, [:id, :kind]))

    actions = if to_notify == [], do: [], else: [notify_parent: {:new_tracks, to_notify}]

    negotiated_tracks = negotiated_tracks ++ negotiating_tracks

    state =
      %{state | negotiated_tracks: negotiated_tracks, negotiating_tracks: []}
      |> maybe_negotiate_tracks()

    {actions, state}
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

    state = %{state | pc: pc, status: :connecting}
    Process.monitor(state.signaling.pid)
    send(state.signaling.pid, {:register_element, self()})
    maybe_negotiate_tracks(state)
  end

  defp maybe_negotiate_tracks(%{negotiating_tracks: negotiating_tracks} = state)
       when negotiating_tracks != [] do
    state
  end

  defp maybe_negotiate_tracks(%{queued_tracks: []} = state) do
    state
  end

  defp maybe_negotiate_tracks(%{queued_tracks: queued_tracks} = state) do
    negotiating_tracks =
      Enum.map(queued_tracks, fn track ->
        webrtc_track = MediaStreamTrack.new(track.kind)
        PeerConnection.add_track(state.pc, webrtc_track)
        Map.put(track, :id, webrtc_track.id)
      end)

    {:ok, offer} = PeerConnection.create_offer(state.pc)
    :ok = PeerConnection.set_local_description(state.pc, offer)
    send(state.signaling.pid, {:element, offer})
    %{state | negotiating_tracks: negotiating_tracks, queued_tracks: []}
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
