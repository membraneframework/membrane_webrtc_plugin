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
      case Membrane.WebRTC.PhoenixSignaling.Registry.get(signaling_id) do
        nil ->
          {:stop, :normal, socket}

        signaling ->
          msg = Jason.decode!(msg)
          Membrane.WebRTC.Signaling.signal(signaling, msg)
          {:noreply, socket}
      end
    end

    @impl true
    def handle_info({:membrane_webrtc_signaling, _pid, msg, _metadata}, socket) do
      push(socket, socket.assigns.signaling_id, msg)
      {:noreply, socket}
    end
  end
end
