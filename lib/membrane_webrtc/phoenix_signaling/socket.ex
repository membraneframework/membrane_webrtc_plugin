defmodule Membrane.WebRTC.PhoenixSignaling.Socket do
  @moduledoc """
  Phoenix Socket implementation which directs all topics to a Phoenix Channel capable of processing
  WebRTC signaling messages.

  To use PhoenixSignaling, you need to:
  1. Create Socket in your application endpoint, for instance:
  ```
    socket "/signaling", Membrane.WebRTC.PhoenixSignaling.Socket,
    websocket: true,
    longpoll: false
  ```
  2. Create signaling channel with desired signaling ID:
  ```
    signaling = PhoenixSignaling.new("signaling_id")
  ```
  3. Use the Phoenix Socket to exchange WebRTC signaling data:
  ```
  let socket = new Socket("/singaling", {params: {token: window.userToken}})
  socket.connect()
  let channel = socket.channel('signaling_id')
  channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp)
      // here you can exchange WebRTC data
    })
    .receive("error", resp => { console.log("Unable to join", resp) })

  ```
  """
  use Phoenix.Socket

  channel("*", Membrane.WebRTC.PhoenixSignaling.Channel)

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
