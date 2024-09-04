# this module forwards rtp packets to source_whip

defmodule Membrane.WebRTC.WhipWhep.Forwarder do
  use GenServer

  require Logger

  alias Membrane.WebRTC.WhipWhep.PeerSupervisor
  alias ExWebRTC.PeerConnection

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(source_pid: source_pid) do
    GenServer.start_link(__MODULE__, %{source_pid: source_pid}, name: __MODULE__)
  end

  @spec connect_input(pid()) :: :ok
  def connect_input(pc) do
    GenServer.call(__MODULE__, {:connect_input, pc})
  end

  @impl true
  def init(opts) do
    state = %{
      input_pc: nil,
      audio_input: nil,
      video_input: nil,
      source_pid: opts.source_pid
    }

    IO.inspect(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:connect_input, pc}, _from, state) do
    if state.input_pc != nil do
      PeerSupervisor.terminate_pc(state.input_pc)
    end

    PeerConnection.controlling_process(pc, self())
    {audio_track_id, video_track_id} = get_tracks(pc, :receiver)

    Logger.info("Successfully added input #{inspect(pc)}")

    state = %{state | input_pc: pc, audio_input: audio_track_id, video_input: video_track_id}
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(
        {:ex_webrtc, pc, {:connection_state_change, :connected}},
        %{input_pc: pc} = state
      ) do
    Logger.info("exWebRTC Input #{inspect(pc)} has successfully connected")
    send(state.source_pid, :peer_connected)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:ex_webrtc, input_pc, {:rtp, id, nil, packet}},
        %{input_pc: input_pc, audio_input: id} = state
      ) do
    send(state.source_pid, {:audio_packet, id, packet})
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:ex_webrtc, input_pc, {:rtp, id, nil, packet}},
        %{input_pc: input_pc, video_input: id} = state
      ) do
    send(state.source_pid, {:video_packet, id, packet})
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:rtcp, packets}}, state) do
    for packet <- packets do
      case packet do
        {_track_id, %ExRTCP.Packet.PayloadFeedback.PLI{}} when state.input_pc != nil ->
          :ok = PeerConnection.send_pli(state.input_pc, state.video_input)

        _other ->
          :ok
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp get_tracks(pc, type) do
    transceivers = PeerConnection.get_transceivers(pc)
    audio_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :audio end)
    video_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :video end)

    audio_track_id = Map.fetch!(audio_transceiver, type).track.id
    video_track_id = Map.fetch!(video_transceiver, type).track.id

    {audio_track_id, video_track_id}
  end
end
