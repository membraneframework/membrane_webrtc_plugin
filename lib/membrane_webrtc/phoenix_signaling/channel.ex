defmodule Membrane.WebRTC.PhoenixSignaling.Channel do
  use Phoenix.Channel
  alias Membrane.WebRTC.{PhoenixSignaling, Signaling}

  @impl true
  def join(signaling_id, _payload, socket) do
    signaling = PhoenixSignaling.get_or_create(signaling_id)
    Signaling.register_peer(signaling, message_format: :json_data)
    socket = assign(socket, :signaling_id, signaling_id)
    {:ok, socket}
  end

  @impl true
  def handle_in(signaling_id, msg, socket) do
    msg = Jason.decode!(msg)
    signaling = PhoenixSignaling.get!(signaling_id)
    Signaling.signal(signaling, msg)
    {:noreply, socket}
  end

  @impl true
  def handle_info({Signaling, _pid, msg, _metadata}, socket) do
    push(socket, socket.assigns.signaling_id, msg)
    {:noreply, socket}
  end
end
