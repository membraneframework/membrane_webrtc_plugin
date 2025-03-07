defmodule Membrane.WebRTC.PhoenixSignaling do
  @moduledoc """
  Provides signaling capabilities for WebRTC connections through Phoenix channels.
  """
  use GenServer
  alias Membrane.WebRTC.Signaling

  @typedoc """
  A type representing an unique identifier that is used to distinguish between different Phoenix Signaling
  instances.
  """
  @type signaling_id :: String.t()

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

  @spec start(term()) :: GenServer.on_start()
  def start(args) do
    GenServer.start(__MODULE__, args, name: __MODULE__)
  end

  @spec start(term()) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {:ok, _registry_pid} = Registry.start_link(keys: :unique, name: __MODULE__.Registry)
    {:ok, %{}}
  end

  @doc """
  Returns an instance of a Phoenix Signaling associated with given signaling ID.
  """
  @spec new(signaling_id()) :: Signaling.t()
  def new(signaling_id) do
    get_or_create(signaling_id)
  end

  @doc """
  Registers Phoenix.Channel process as WebRTC signaling peer
  so that it can send and receive signaling messages.
  """
  @spec register_channel(signaling_id(), pid() | nil) :: :ok
  def register_channel(signaling_id, channel_pid \\ nil) do
    channel_pid = channel_pid || self()
    signaling = get_or_create(signaling_id)
    Signaling.register_peer(signaling, message_format: :json_data, pid: channel_pid)
  end

  @doc """
  Sends a signal message via the Phoenix Signaling instance associated with given signaling ID.
  """
  @spec signal(signaling_id(), Signaling.message_content()) :: :ok
  def signal(signaling_id, msg) do
    signaling = get!(signaling_id)
    Signaling.signal(signaling, msg)
  end

  defp get_or_create(signaling_id) do
    GenServer.call(__MODULE__, {:get_or_create, signaling_id})
  end

  defp get!(signaling_id) do
    [{_pid, signaling}] = Registry.lookup(__MODULE__.Registry, signaling_id)
    signaling
  end
end
