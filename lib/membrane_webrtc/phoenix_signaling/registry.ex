if Code.ensure_loaded?(Phoenix) do
  defmodule Membrane.WebRTC.PhoenixSignaling.Registry do
    @moduledoc false
    use GenServer
    alias Membrane.WebRTC.PhoenixSignaling
    alias Membrane.WebRTC.Signaling

    @spec start(term()) :: GenServer.on_start()
    def start(args) do
      GenServer.start(__MODULE__, args, name: __MODULE__)
    end

    @spec start_link(term()) :: GenServer.on_start()
    def start_link(args) do
      GenServer.start_link(__MODULE__, args, name: __MODULE__)
    end

    @spec get_or_create(PhoenixSignaling.signaling_id()) :: Signaling.t()
    def get_or_create(signaling_id) do
      GenServer.call(__MODULE__, {:get_or_create, signaling_id})
    end

    @spec get(PhoenixSignaling.signaling_id()) :: Signaling.t() | nil
    def get(signaling_id) do
      GenServer.call(__MODULE__, {:get, signaling_id})
    end

    @spec get!(PhoenixSignaling.signaling_id()) :: Signaling.t() | no_return()
    def get!(signaling_id) do
      case get(signaling_id) do
        nil ->
          raise "Couldn't find signaling instance associated with signaling_id: #{inspect(signaling_id)}"

        signaling ->
          signaling
      end
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
