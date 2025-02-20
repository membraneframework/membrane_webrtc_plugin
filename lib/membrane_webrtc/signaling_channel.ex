defmodule Membrane.WebRTC.SignalingChannel do
  @moduledoc """
  Deprecated since v0.24.0. Use #{inspect(Membrane.WebRTC.Signaling)} instead.
  """
  require Logger

  alias Membrane.WebRTC.Signaling

  @type t :: Signaling.t()
  @type message :: Signaling.message()
  @type message_content :: Signaling.message_content()
  @type ex_webrtc_message :: Signaling.ex_webrtc_message()
  @type json_data_message :: Signaling.json_data_message()

  @spec new() :: t
  def new() do
    Logger.warning("""
    Module #{inspect(__MODULE__)} is deprecated since v0.24.0. Use #{inspect(Signaling)} instead.
    """)

    Signaling.new()
  end

  @spec register_peer(t, message_format: :ex_webrtc | :json_data, pid: pid) :: :ok
  defdelegate register_peer(signaling, opts \\ []), to: Signaling

  @spec register_element(t) :: :ok
  def register_element(signaling), do: Signaling.register_element(signaling)

  @spec signal(t, message_content, metadata :: map) :: :ok
  defdelegate signal(signaling, message, metadata \\ %{}), to: Signaling

  @spec close(t) :: :ok
  defdelegate close(signaling), to: Signaling
end
