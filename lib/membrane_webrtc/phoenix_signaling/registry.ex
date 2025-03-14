if Code.ensure_loaded?(Phoenix) do
  defmodule Membrane.WebRTC.PhoenixSignaling.Registry do
    use GenServer
    alias Membrane.WebRTC.Signaling

    @spec start(term()) :: GenServer.on_start()
    def start(args) do
      GenServer.start(__MODULE__, args, name: __MODULE__)
    end

    @spec start_link(term()) :: GenServer.on_start()
    def start_link(args) do
      GenServer.start_link(__MODULE__, args, name: __MODULE__)
    end

    @impl true
    def init(_args) do
      {:ok, %{signaling_map: %{}}}
    end

    @impl true
    def handle_call({:get_or_create, signaling_id}, _from, state) do
      case Map.get(state.signaling_map, signaling_id) do
        nil ->
          signaling = Signaling.new()
          state = put_in(state, [:signaling_map, signaling_id], signaling)
          {:reply, signaling, state}

        signaling ->
          {:reply, signaling, state}
      end
    end

    @impl true
    def handle_call({:get, signaling_id}, _from, state) do
      {:reply, Map.get(state.signaling_map, signaling_id), state}
    end
  end
end
