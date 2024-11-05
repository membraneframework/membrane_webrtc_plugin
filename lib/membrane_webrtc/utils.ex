defmodule Membrane.WebRTC.Utils do
  @moduledoc false

  alias Membrane.WebRTC.{SignalingChannel, SimpleWebSocketServer}

  @spec validate_signaling!(SignalingChannel.t() | {:websocket, SimpleWebSocketServer.options()}) ::
          :ok | no_return()
  def validate_signaling!(%SignalingChannel{}), do: :ok

  def validate_signaling!({:websocket, options}) do
    _options = SimpleWebSocketServer.validate_options!(options)
    :ok
  end

  def validate_signaling!({:whip, options} = signaling) when is_list(options) do
    options
    |> Enum.each(fn
      {atom, _term} when is_atom(atom) -> :ok
      _other -> do_raise(signaling)
    end)

    :ok
  end

  def validate_signaling!(signaling), do: do_raise(signaling)

  defp do_raise(signaling) do
    raise "BCD"
    raise "Invalid signaling: #{inspect(signaling, pretty: true)}"
  end
end
