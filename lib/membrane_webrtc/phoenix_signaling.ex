if Code.ensure_loaded?(Phoenix) do
  defmodule Membrane.WebRTC.PhoenixSignaling do
    @moduledoc """
    Provides signaling capabilities for WebRTC connections through Phoenix channels.
    """
    alias Membrane.WebRTC.Signaling

    @typedoc """
    A type representing an unique identifier that is used to distinguish between different Phoenix Signaling
    instances.
    """
    @type signaling_id :: String.t()

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
    @spec signal(signaling_id(), Signaling.message_content()) :: :ok | no_return()
    def signal(signaling_id, msg) do
      signaling = get!(signaling_id)
      Signaling.signal(signaling, msg)
    end

    defp get_or_create(signaling_id) do
      GenServer.call(__MODULE__.Registry, {:get_or_create, signaling_id})
    end

    defp get!(signaling_id) do
      case GenServer.call(__MODULE__.Registry, {:get, signaling_id}) do
        nil ->
          raise "Couldn't find signaling instance associated with signaling_id: #{inspect(signaling_id)}"

        signaling ->
          signaling
      end
    end
  end
end
