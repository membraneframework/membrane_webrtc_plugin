defmodule Membrane.WebRTC.ExWebRTCSource do
  use Membrane.Endpoint

  require Membrane.Logger

  alias ExWebRTC.ICECandidate
  alias ExWebRTC.SessionDescription
  alias ExWebRTC.{PeerConnection, RTPCodecParameters}
  alias Membrane.WebRTC.SignalingChannel

  def_options signaling_channel: []

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
       output_tracks: %{},
       awaiting_outputs: %{},
       signaling: opts.signaling_channel,
       status: :init
     }}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {:ok, pc} =
      PeerConnection.start(
        ice_servers: @ice_servers,
        video_codecs: @video_codecs,
        audio_codecs: @audio_codecs
      )

    Process.monitor(pc)

    Process.monitor(state.signaling.pid)
    send(state.signaling.pid, {:register_element, self()})

    {[], %{state | pc: pc, status: :connecting}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, kind) = pad, %{playback: :stopped}, state) do
    state = put_in(state, [:awaiting_outputs, kind], pad)
    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, pad_id) = pad, _ctx, state) do
    {:queue, queue} = state.output_tracks[pad_id]
    buffers = Enum.reverse(queue)
    state = put_in(state, [:output_tracks, pad_id], {:connected, pad})
    {[stream_format: {pad, %Membrane.RTP{}}, buffer: {pad, buffers}], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, _msg}, _ctx, %{status: :closed} = state) do
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:track, track}}, _ctx, state) do
    if pad = state.awaiting_outputs[track.kind] do
      state =
        state
        |> put_in([:output_tracks, track.id], {:connected, pad})
        |> Bunch.Access.delete_in([:awaiting_outputs, track.kind])

      {[stream_format: {pad, %Membrane.RTP{}}], state}
    else
      state = put_in(state, [:output_tracks, track.id], {track, {:queue, []}})
      {[notify_parent: {:new_track, track}], state}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:rtp, id, packet}}, _ctx, state) do
    buffer = %Membrane.Buffer{
      payload: packet.payload,
      metadata: %{rtp: packet |> Map.from_struct() |> Map.delete(:payload)}
    }

    %{output_tracks: output_tracks} = state

    case output_tracks[id] do
      {:connected, pad} ->
        {[buffer: {pad, buffer}], state}

      {:queue, queue} ->
        {[], %{state | output_tracks: %{output_tracks | id => {:queue, [buffer | queue]}}}}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:ice_candidate, candidate}}, _ctx, state) do
    send(state.signaling.pid, {:element, candidate})
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:connection_state_change, :connected}}, _ctx, state) do
    {[], %{state | status: :connected}}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, _message}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({SignalingChannel, %SessionDescription{type: :offer} = sdp}, _ctx, state) do
    :ok = PeerConnection.set_remote_description(state.pc, sdp)
    {:ok, answer} = PeerConnection.create_answer(state.pc)
    :ok = PeerConnection.set_local_description(state.pc, answer)
    send(state.signaling.pid, {:element, answer})
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
    # PeerConnection.close(state.pc)

    handle_close(ctx, state)
  end

  @impl true
  def handle_info(
        {:DOWN, _monitor, :process, pc, _reason},
        ctx,
        %{pc: pc} = state
      ) do
    handle_close(ctx, state)
  end

  defp handle_close(%{playback: :playing} = ctx, %{status: status} = state)
       when status != :closed do
    actions =
      ctx.pads
      |> Map.values()
      |> Enum.filter(&(&1.direction == :output))
      |> Enum.map(&{:end_of_stream, &1.ref})

    {actions, %{state | status: :closed}}
  end

  defp handle_close(_ctx, state) do
    {[], %{state | status: :closed}}
  end
end
