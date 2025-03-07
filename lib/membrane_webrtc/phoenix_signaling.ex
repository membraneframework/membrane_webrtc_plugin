defmodule Membrane.WebRTC.PhoenixSignaling do
  use GenServer

  alias Membrane.WebRTC.Signaling

  def start(opts) do
    GenServer.start(__MODULE__, opts, name: __MODULE__)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, _registry_pid} = Registry.start_link(keys: :unique, name: __MODULE__.Registry)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_or_create, signaling_id}, _from, state) do
    signaling =
      case Registry.lookup(__MODULE__.Registry, signaling_id) do
        [] ->
          signaling = Signaling.new()
          Registry.register(__MODULE__.Registry, signaling_id, signaling)
          signaling

        [{_pid, signaling}] ->
          signaling
      end

    {:reply, signaling, state}
  end

  def get_or_create(signaling_id) do
    GenServer.call(__MODULE__, {:get_or_create, signaling_id})
  end

  def get!(signaling_id) do
    [{_pid, signaling}] = Registry.lookup(__MODULE__.Registry, signaling_id)
    signaling
  end
end
