defmodule Membrane.WebRTC.SignalingChannel do
  use GenServer

  require Logger

  alias ExWebRTC.{ICECandidate, SessionDescription}

  @enforce_keys [:pid]
  defstruct @enforce_keys

  def new(opts \\ []) do
    opts = Keyword.validate!(opts, message_format: :term, peer_pid: self())
    {:ok, pid} = GenServer.start_link(__MODULE__, opts)
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
  def init(opts) do
    state = %{
      peer_pid: opts[:peer_pid],
      message_format: opts[:message_format],
      element_pid: nil,
      msgs_from_peer: []
    }

    Process.monitor(state.peer_pid)
    {:ok, state}
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
        {:DOWN, _monitor, :process, element_pid, reason},
        %{element_pid: element_pid} = state
      ) do
    {:stop, reason, state}
  end

  @impl true
  def handle_info(
        {:DOWN, _monitor, :process, peer_pid, _reason},
        %{peer_pid: peer_pid} = state
      ) do
    {:stop, :normal, state}
  end

  defp send_peer(message, %{message_format: :term} = state) do
    send(state.peer_pid, {__MODULE__, self(), message})
  end

  defp send_peer(message, %{message_format: :json_data} = state) do
    json =
      case message do
        %ICECandidate{} ->
          %{"type" => "ice_candidate", "data" => ICECandidate.to_json(message)}

        %SessionDescription{type: type} ->
          %{"type" => "sdp_#{type}", "data" => SessionDescription.to_json(message)}
      end

    send(state.peer_pid, {__MODULE__, self(), json})
  end

  defp send_element(message, %{message_format: :term} = state) do
    send(state.element_pid, {__MODULE__, self(), message})
  end

  defp send_element(message, %{message_format: :json_data} = state) do
    message =
      case message do
        %{"type" => "ice_candidate", "data" => candidate} -> ICECandidate.from_json(candidate)
        %{"type" => "sdp_offer", "data" => offer} -> SessionDescription.from_json(offer)
        %{"type" => "sdp_answer", "data" => answer} -> SessionDescription.from_json(answer)
      end

    send(state.element_pid, {__MODULE__, self(), message})
  end
end
