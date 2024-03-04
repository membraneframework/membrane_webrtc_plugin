defmodule Membrane.WebRTC.ExWebRTCSink do
  use Membrane.Endpoint

  require Membrane.Logger

  alias ExWebRTC.{
    ICECandidate,
    MediaStreamTrack,
    PeerConnection,
    RTPCodecParameters,
    SessionDescription
  }

  alias Membrane.WebRTC.{SignalingChannel, SimpleWebSocketServer}

  def_options signaling_channel: [], tracks: []

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request,
    options: [kind: []]

  def_output_pad :output,
    accepted_format: Membrane.RTP,
    availability: :on_request,
    flow_control: :push

  @ice_servers [
    %{urls: "stun:stun.l.google.com:19302"}
  ]

  @video_codecs [
    %RTPCodecParameters{
      payload_type: 102,
      mime_type: "video/H264",
      clock_rate: 90_000
    }
  ]

  @audio_codecs [
    %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }
  ]

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %{
       pc: nil,
       input_tracks: %{},
       awaiting_tracks: Enum.map(opts.tracks, &%{kind: &1, id: nil}),
       signaling: opts.signaling_channel,
       status: :init
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
    input_tracks = Map.put(input_tracks, pad, track.id)
    state = %{state | awaiting_tracks: awaiting_tracks, input_tracks: input_tracks}
    {[], state}
  end

  @impl true
  def handle_buffer(pad, buffer, _ctx, %{status: :connected} = state) do
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
  def handle_info({:ex_webrtc, _from, _message}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({SignalingChannel, %SessionDescription{type: :answer} = sdp}, _ctx, state) do
    :ok = PeerConnection.set_remote_description(state.pc, sdp)
    {[], state}
  end

  @impl true
  def handle_info({SignalingChannel, %ICECandidate{} = candidate}, _ctx, state) do
    :ok = PeerConnection.add_ice_candidate(state.pc, candidate)
    {[], state}
  end

  @impl true
  def handle_info(
        {:DOWN, _monitor, :process, signaling_pid, _reason},
        ctx,
        %{signaling: %{pid: signaling_pid}} = state
      ) do
    PeerConnection.close(state.pc)

    actions =
      ctx.pads
      |> Map.values()
      |> Enum.filter(&(&1.direction == :output))
      |> Enum.map(&{:end_of_stream, &1.ref})

    {actions, %{state | status: :closed}}
  end

  defp start_pc(state) do
    {:ok, pc} =
      PeerConnection.start_link(
        ice_servers: @ice_servers,
        video_codecs: @video_codecs,
        audio_codecs: @audio_codecs
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
    timestamp =
      Membrane.Time.divide_by_timebase(buffer.pts, Ratio.new(Membrane.Time.second(), 90_000))

    packet =
      ExRTP.Packet.new(buffer.payload,
        payload_type: 96,
        timestamp: timestamp,
        marker: buffer.metadata.rtp.marker
      )

    PeerConnection.send_rtp(state.pc, state.input_tracks[pad], packet)
  end
end
