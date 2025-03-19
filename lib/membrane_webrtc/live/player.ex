if Code.ensure_loaded?(Phoenix) and Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule Membrane.WebRTC.Live.Player do
    @moduledoc ~S'''
    LiveView for playing audio and video get via WebRTC from `Membrane.WebRTC.Sink`.

    It:
    * renders a single HTMLVideoElement.
    * creates WebRTC PeerConnection on the browser side.
    * forwards signaling messages between the browser and `Membrane.WebRTC.Sink` via `Membrane.WebRTC.Signaling`.
    * attaches audio and video from the Elixir to the HTMLVideoElement.

    ## JavaScript Hook

    Player live view requires JavaScript hook to be registered under `Player` name.
    The hook can be created using `createPlayerHook` function.
    For example:

    ```javascript
    import { createPlayerHook } from "membrane_webrtc_plugin";
    let Hooks = {};
    const iceServers = [{ urls: "stun:stun.l.google.com:19302" }];
    Hooks.Player = createPlayerHook(iceServers);
    let liveSocket = new LiveSocket("/live", Socket, {
      // ...
      hooks: Hooks
    });
    ```

    ## Examples

    ```elixir
    defmodule StreamerWeb.StreamViewerLive do
      use StreamerWeb, :live_view

      alias Membrane.WebRTC.Live.Player

      @impl true
      def render(assigns) do
      ~H"""
      <Player.live_render socket={@socket} player_id={"player"} />
      """
      end

      @impl true
      def mount(_params, _session, socket) do
        signaling = Membrane.WebRTC.Signaling.new()
        {:ok, _supervisor, _pipelne} = Membrane.Pipeline.start_link(MyPipeline, signaling: signaling)

        socket = socket |> Player.attach(id: "player", signaling: signaling)
        {:ok, socket}
      end
    end
    ```
    '''
    use Phoenix.LiveView
    require Logger

    alias Membrane.WebRTC.Signaling

    @type t() :: %__MODULE__{
            id: String.t(),
            signaling: Signaling.t()
          }

    defstruct id: nil, signaling: nil

    attr(:socket, Phoenix.LiveView.Socket, required: true, doc: "Parent live view socket")

    attr(:player_id, :string,
      required: true,
      doc: """
      ID of a `player` previously attached to the socket. It has to be the same as the value passed to `:id`
      field `#{inspect(__MODULE__)}.attach/2`.
      """
    )

    attr(:class, :string, default: nil, doc: "CSS/Tailwind classes for styling")

    @doc """
    Helper function for rendering Player live view.
    """
    def live_render(assigns) do
      ~H"""
      <%= live_render(@socket, __MODULE__, id: "#{@player_id}-lv", session: %{"class" => @class, "id" => @player_id}) %>
      """
    end

    @doc """
      Attaches required hooks and creates `#{inspect(__MODULE__)}` struct.

    Created struct is saved in socket's assigns (in `socket.assigns[#{inspect(__MODULE__)}][id]`) and then
    it is sent by an attached hook to a child live view process.

    Options:
    * `id` - player id. It is used to identify live view and generated HTML video player. It must be unique
    withing single page.
    * `signaling` - `Membrane.WebRTC.Signaling.t()`, that has been passed to `Membrane.WebRTC.Sink` as well.
    """
    @spec attach(Phoenix.LiveView.Socket.t(), Keyword.t()) :: Phoenix.LiveView.Socket.t()
    def attach(socket, opts) do
      opts = opts |> Keyword.validate!([:id, :signaling])
      player = struct!(__MODULE__, opts)

      all_players =
        socket.assigns
        |> Map.get(__MODULE__, %{})
        |> Map.put(player.id, player)

      socket
      |> assign(__MODULE__, all_players)
      |> detach_hook(:player_handshake, :handle_info)
      |> attach_hook(:player_handshake, :handle_info, &parent_handshake/2)
    end

    @spec get_attached(Phoenix.LiveView.Socket.t(), String.t()) :: t()
    def get_attached(socket, id), do: socket.assigns[__MODULE__][id]

    ## CALLBACKS

    @impl true
    def render(%{player: nil} = assigns) do
      ~H"""
      """
    end

    @impl true
    def render(assigns) do
      ~H"""
      <video id={@player.id} phx-hook="Player" class={@class} controls autoplay muted></video>
      """
    end

    @impl true
    def mount(_params, %{"class" => class, "id" => id}, socket) do
      socket = socket |> assign(class: class, player: nil)

      socket =
        if connected?(socket),
          do: client_handshake(socket, id),
          else: socket

      {:ok, socket}
    end

    defp parent_handshake({__MODULE__, {:connected, id, player_pid}}, socket) do
      player_struct =
        socket.assigns
        |> Map.fetch!(__MODULE__)
        |> Map.fetch!(id)

      send(player_pid, player_struct)

      {:halt, socket}
    end

    defp parent_handshake(_msg, socket) do
      {:cont, socket}
    end

    defp client_handshake(socket, id) do
      send(socket.parent_pid, {__MODULE__, {:connected, id, self()}})

      receive do
        %__MODULE__{} = player ->
          player.signaling
          |> Signaling.register_peer(message_format: :json_data)

          socket |> assign(player: player)
      after
        5000 -> exit(:timeout)
      end
    end

    @impl true
    def handle_info({:membrane_webrtc_signaling, _pid, message, _metadata}, socket) do
      Logger.debug("""
      #{log_prefix(socket.assigns.player.id)} Sent WebRTC signaling message: #{inspect(message, pretty: true)}
      """)

      {:noreply,
       socket
       |> push_event("webrtc_signaling-#{socket.assigns.player.id}", message)}
    end

    @impl true
    def handle_event("webrtc_signaling", message, socket) do
      Logger.debug("""
      #{log_prefix(socket.assigns.player.id)} Received WebRTC signaling message: #{inspect(message, pretty: true)}
      """)

      if message["data"] do
        socket.assigns.player.signaling
        |> Signaling.signal(message)
      end

      {:noreply, socket}
    end

    defp log_prefix(id), do: [module: __MODULE__, id: id] |> inspect()
  end
end
