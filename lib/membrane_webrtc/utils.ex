defmodule Membrane.WebRTC.Utils do
  @moduledoc false

  alias Membrane.WebRTC.{Signaling, SimpleWebSocketServer}

  @spec validate_signaling!(
          Signaling.t()
          | {:websocket, SimpleWebSocketServer.options()}
          | {:whip, [{atom(), term()}]}
        ) ::
          :ok | no_return()
  def validate_signaling!(%Signaling{}), do: :ok

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

  @spec do_raise(term()) :: no_return()
  defp do_raise(signaling) do
    raise "Invalid signaling: #{inspect(signaling)}"
  end
end
