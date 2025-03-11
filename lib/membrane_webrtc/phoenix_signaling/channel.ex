if Code.ensure_loaded?(Phoenix) do
  defmodule Membrane.WebRTC.PhoenixSignaling.Channel do
    @moduledoc false
    use Phoenix.Channel
    alias Membrane.WebRTC.PhoenixSignaling

    @impl true
    def join(signaling_id, _payload, socket) do
      PhoenixSignaling.register_channel(signaling_id)
      socket = assign(socket, :signaling_id, signaling_id)
      {:ok, socket}
    end

    @impl true
    def handle_in(signaling_id, msg, socket) do
      msg = Jason.decode!(msg)
      PhoenixSignaling.signal(signaling_id, msg)
      {:noreply, socket}
    end

    @impl true
    def handle_info({Membrane.WebRTC.Signaling, _pid, msg, _metadata}, socket) do
      push(socket, socket.assigns.signaling_id, msg)
      {:noreply, socket}
    end
  end
end
