defmodule Membrane.WebRTC.SignalingChannel do
  use GenServer

  alias ExWebRTC.{ICECandidate, SessionDescription}

  @enforce_keys [:pid]
  defstruct @enforce_keys

  def new(mode, pid \\ self()) do
    {:ok, pid} = GenServer.start_link(__MODULE__, %{mode: mode, peer_pid: pid})
    %__MODULE__{pid: pid}
  end

  def signal(%__MODULE__{pid: pid}, message) do
    send(pid, {:peer, message})
    :ok
  end

  def close(%__MODULE__{pid: pid}) do
    GenServer.stop(pid)
  end

  @impl true
  def init(%{mode: mode, peer_pid: peer_pid}) do
    {:ok, %{peer_pid: peer_pid, mode: mode, element_pid: nil, msgs_from_peer: []}}
  end

  @impl true
  def handle_info({:peer, message}, %{element_pid: nil} = state) do
    {:noreply, %{state | msgs_from_peer: [message | state.msgs_from_peer]}}
  end

  @impl true
  def handle_info({:peer, message}, state) do
    send_element(message, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:element, message}, state) do
    send_peer(message, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:register_element, pid}, state) do
    Process.monitor(pid)
    state = %{state | element_pid: pid}

    state.msgs_from_peer
    |> Enum.reverse()
    |> Enum.each(&send_element(&1, state))

    {:noreply, %{state | msgs_from_peer: []}}
  end

  @impl true
  def handle_info(
        {:DOWN, _monitor, element_pid, :process, reason},
        %{element_pid: element_pid} = state
      ) do
    {:stop, reason, state}
  end

  defp send_peer(message, %{mode: :term} = state) do
    send(state.peer_pid, {__MODULE__, message})
  end

  defp send_peer(message, %{mode: :json_data} = state) do
    json =
      case message do
        %ICECandidate{} ->
          %{"type" => "ice_candidate", "data" => ICECandidate.to_json(message)}

        %SessionDescription{type: type} ->
          %{"type" => "sdp_#{type}", "data" => SessionDescription.to_json(message)}
      end

    send(state.peer_pid, {__MODULE__, json})
  end

  defp send_element(message, %{mode: :term} = state) do
    send(state.element_pid, {__MODULE__, message})
  end

  defp send_element(message, %{mode: :json_data} = state) do
    message =
      case message do
        %{"type" => "ice_candidate", "data" => candidate} -> ICECandidate.from_json(candidate)
        %{"type" => "sdp_offer", "data" => offer} -> SessionDescription.from_json(offer)
        %{"type" => "sdp_answer", "data" => answer} -> SessionDescription.from_json(answer)
      end

    send(state.element_pid, {__MODULE__, message})
  end
end
