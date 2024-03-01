defmodule Membrane.WebRTC.ExWebRTCSink do
  use Membrane.Endpoint

  alias ExWebRTC.MediaStreamTrack
  alias ExWebRTC.{PeerConnection, RTPCodecParameters}
  alias Membrane.WebRTC.SignalingChannel

  require Membrane.Logger

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
  def handle_setup(_ctx, state) do
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

    {[setup: :incomplete],
     %{state | awaiting_tracks: awaiting_tracks, pc: pc, status: :connecting}}
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
  def handle_info({:ex_webrtc, _from, _msg}, _ctx, %{status: :closed} = state) do
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:ice_candidate, candidate}}, _ctx, state) do
    send(state.signaling.pid, {:element, {:ice, candidate}})
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
  def handle_info({SignalingChannel, :sdp_offer, sdp}, _ctx, state) do
    :ok = PeerConnection.set_remote_description(state.pc, sdp)
    {:ok, answer} = PeerConnection.create_answer(state.pc)
    :ok = PeerConnection.set_local_description(state.pc, answer)
    send(state.signaling.pid, {:element, {:sdp, answer}})
    {[], state}
  end

  @impl true
  def handle_info({SignalingChannel, :ice_candidate, candidate}, _ctx, state) do
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

  defp send_buffer(pad, buffer, state) do
    ts = buffer.pts
    last_ts = Process.get(:last_packet_ts) || ts
    Process.put(:last_packet_ts, ts)
    ts_diff = Membrane.Time.as_milliseconds(ts - last_ts, :round)

    # if ts - last_ts > 0, do: Process.sleep(30)
    time = Membrane.Time.monotonic_time()
    prev_time = Process.get(:last_packet_time) || time
    Process.put(:last_packet_time, time)
    time_diff = Membrane.Time.as_milliseconds(time - prev_time, :round)
    Membrane.Logger.info("packet ts_diff: #{ts_diff}, time_diff: #{time_diff}")

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
