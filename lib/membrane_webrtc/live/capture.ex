if Code.ensure_loaded?(Phoenix) and Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule Membrane.WebRTC.Live.Capture do
    @moduledoc ~S'''
    LiveView for capturing audio and video from a browser and sending it via WebRTC to `Membrane.WebRTC.Source`.

    *Note:* This module will be available in your code only if you add `{:phoenix, "~> 1.7"}`
    and `{:phoenix_live_view, "~> 1.0"}` to the dependencies of of your root project.

    It:
    * creates WebRTC PeerConnection on the browser side.
    * forwards signaling messages between the browser and `Membrane.WebRTC.Source` via `Membrane.WebRTC.Signaling`.
    * sends audio and video streams to the related `Membrane.WebRTC.Source`.

    ## JavaScript Hook

    Capture LiveView requires JavaScript hook to be registered under `Capture` name.
    The hook can be created using `createCaptureHook` function.
    For example:

    ```javascript
    import { createCaptureHook } from "membrane_webrtc_plugin";
    let Hooks = {};
    const iceServers = [{ urls: "stun:stun.l.google.com:19302" }];
    Hooks.Capture = createCaptureHook(iceServers);
    let liveSocket = new LiveSocket("/live", Socket, {
      // ...
      hooks: Hooks
    });
    ```

    ## Examples

    ```elixir
    defmodule StreamerWeb.StreamSenderLive do
      use StreamerWeb, :live_view

      alias Membrane.WebRTC.Live.Capture

      @impl true
      def render(assigns) do
      ~H"""
      <Capture.live_render socket={@socket} capture_id="capture" />
      """
      end

      @impl true
      def mount(_params, _session, socket) do
        signaling = Membrane.WebRTC.Signaling.new()
        {:ok, _supervisor, _pipelne} = Membrane.Pipeline.start_link(MyPipeline, signaling: signaling)

        socket = socket |> Capture.attach(id: "capture", signaling: signaling)
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
            signaling: Signaling.t(),
            preview?: boolean(),
            audio?: boolean(),
            video?: boolean()
          }

    defstruct id: nil, signaling: nil, video?: true, audio?: true, preview?: true

    attr(:socket, Phoenix.LiveView.Socket, required: true, doc: "Parent live view socket")

    attr(:capture_id, :string,
      required: true,
      doc: """
      ID of a `caputre` previously attached to the socket. It has to be the same as the value passed to `:id`
      field `#{inspect(__MODULE__)}.attach/2`.
      """
    )

    attr(:class, :string, default: "", doc: "CSS/Tailwind classes for styling")

    @doc """
    Helper function for rendering Capture LiveView.
    """
    def live_render(assigns) do
      ~H"""
      <%= live_render(@socket, __MODULE__, id: "#{@capture_id}-lv", session: %{"class" => @class, "id" => @capture_id}) %>
      """
    end

    @doc """
    Attaches required hooks and creates `#{inspect(__MODULE__)}` struct.

    Created struct is saved in socket's assigns and then
    it is sent by an attached hook to a child LiveView process.

    Options:
    * `id` - capture id. It is used to identify live view and generated HTML video player. It must be unique
    within single page.
    * `signaling` - `Membrane.WebRTC.Signaling.t()`, that has been passed to `Membrane.WebRTC.Source` as well.
    * `video?` - if `true`, the video stream from the computer camera will be captured. Defaults to `true`.
    * `audio?` - if `true`, the audio stream from the computer microphone will be captured. Defaults to `true`.
    * `preview?` - if `true`, the function `#{inspect(__MODULE__)}.live_render/1` will return a video HTML tag
    with attached captured video stream. Defaults to `true`.
    """
    @spec attach(Phoenix.LiveView.Socket.t(), Keyword.t()) :: Phoenix.LiveView.Socket.t()
    def attach(socket, opts) do
      opts =
        opts
        |> Keyword.validate!([
          :id,
          :signaling,
          video?: true,
          audio?: true,
          preview?: true
        ])

      capture = struct!(__MODULE__, opts)

      all_captures =
        socket.assigns
        |> Map.get(__MODULE__, %{})
        |> Map.put(capture.id, capture)

      socket
      |> assign(__MODULE__, all_captures)
      |> detach_hook(:capture_handshake, :handle_info)
      |> attach_hook(:capture_handshake, :handle_info, &parent_handshake/2)
    end

    @spec get_attached(Phoenix.LiveView.Socket.t(), String.t()) :: t()
    def get_attached(socket, id), do: socket.assigns[__MODULE__][id]

    ## CALLBACKS

    @impl true
    def render(%{capture: nil} = assigns) do
      ~H"""
      """
    end

    @impl true
    def render(%{capture: %__MODULE__{preview?: true}} = assigns) do
      ~H"""
      <video id={@capture.id} phx-hook="Capture" class={@class} muted style="
        -o-transform: scaleX(-1);
        -moz-transform: scaleX(-1);
        -webkit-transform: scaleX(-1);
        -ms-transform: scaleX(-1);
        transform: scaleX(-1);
      "></video>
      """
    end

    @impl true
    def render(%{capture: %__MODULE__{preview?: false}} = assigns) do
      ~H"""
      <video id={@capture.id} phx-hook="Capture" class={@class} muted style="display: none;"></video>
      """
    end

    @impl true
    def mount(_params, %{"class" => class, "id" => id}, socket) do
      socket = socket |> assign(class: class, capture: nil)

      socket =
        if connected?(socket),
          do: client_handshake(socket, id),
          else: socket

      {:ok, socket}
    end

    defp parent_handshake({__MODULE__, {:connected, id, capture_pid}}, socket) do
      capture_struct =
        socket.assigns
        |> Map.fetch!(__MODULE__)
        |> Map.fetch!(id)

      send(capture_pid, capture_struct)

      {:halt, socket}
    end

    defp parent_handshake(_msg, socket) do
      {:cont, socket}
    end

    defp client_handshake(socket, id) do
      send(socket.parent_pid, {__MODULE__, {:connected, id, self()}})

      receive do
        %__MODULE__{} = capture ->
          capture.signaling
          |> Signaling.register_peer(message_format: :json_data)

          media_constraints = %{
            "audio" => capture.audio?,
            "video" => capture.video?
          }

          socket
          |> assign(capture: capture)
          |> push_event("media_constraints-#{capture.id}", media_constraints)
      after
        5000 -> exit(:timeout)
      end
    end

    @impl true
    def handle_info({:membrane_webrtc_signaling, _pid, message, _metadata}, socket) do
      Logger.debug("""
      #{log_prefix(socket.assigns.capture.id)} Sent WebRTC signaling message: #{inspect(message, pretty: true)}
      """)

      {:noreply,
       socket
       |> push_event("webrtc_signaling-#{socket.assigns.capture.id}", message)}
    end

    @impl true
    def handle_event("webrtc_signaling", message, socket) do
      Logger.debug("""
      #{log_prefix(socket.assigns.capture.id)} Received WebRTC signaling message: #{inspect(message, pretty: true)}
      """)

      if message["data"] do
        socket.assigns.capture.signaling
        |> Signaling.signal(message)
      end

      {:noreply, socket}
    end

    defp log_prefix(id), do: [module: __MODULE__, id: id] |> inspect()
  end
end
