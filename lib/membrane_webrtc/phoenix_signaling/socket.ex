defmodule Membrane.WebRTC.PhoenixSignaling.Socket do
  use Phoenix.Socket

  channel("*", Membrane.WebRTC.PhoenixSignaling.Channel)

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
