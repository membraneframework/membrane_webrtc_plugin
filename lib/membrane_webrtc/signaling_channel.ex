defmodule Membrane.WebRTC.SignalingChannel do
  use GenServer

  @enforce_keys [:pid]
  defstruct @enforce_keys

  def new(pid \\ self()) do
    {:ok, pid} = GenServer.start_link(__MODULE__, pid)
    %__MODULE__{pid: pid}
  end

  def sdp(%__MODULE__{pid: pid}, sdp) do
    send(pid, {:peer, {:sdp, sdp}})
    :ok
  end

  def ice_candidate(%__MODULE__{pid: pid}, ice_candidate) do
    send(pid, {:peer, {:ice, ice_candidate}})
    :ok
  end

  def close(%__MODULE__{pid: pid}) do
    GenServer.stop(pid)
  end

  @impl true
  def init(peer_pid) do
    {:ok, %{peer_pid: peer_pid, element_pid: nil, msgs_from_peer: []}}
  end

  @impl true
  def handle_info({:peer, message}, %{element_pid: nil} = state) do
    {:noreply, %{state | msgs_from_peer: [message | state.msgs_from_peer]}}
  end

  @impl true
  def handle_info({:peer, message}, state) do
    forward(state.element_pid, message)
    {:noreply, state}
  end

  @impl true
  def handle_info({:element, message}, state) do
    forward(state.peer_pid, message)
    {:noreply, state}
  end

  @impl true
  def handle_info({:register_element, pid}, state) do
    Process.monitor(pid)

    state.msgs_from_peer
    |> Enum.reverse()
    |> Enum.each(&forward(pid, &1))

    {:noreply, %{state | element_pid: pid, msgs_from_peer: []}}
  end

  @impl true
  def handle_info(
        {:DOWN, _monitor, element_pid, :process, reason},
        %{element_pid: element_pid} = state
      ) do
    {:stop, reason, state}
  end

  @impl true
  def terminate(reason, state) do
    forward(state.peer_pid, {:closed, reason})
    :ok
  end

  defp forward(pid, {type, content}) do
    send(pid, {__MODULE__, type, content})
  end
end
