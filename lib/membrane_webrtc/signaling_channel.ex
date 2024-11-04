defmodule Membrane.WebRTC.SignalingChannel do
  @moduledoc """
  Channel for sending WebRTC signaling messages between Membrane elements
  and other WebRTC peers.

  The flow of using the signaling channel is the following:
  - Create it with `new/0`.
  - Register the peer process (the one to send and receive signaling messages)
    with `register_peer/2`.
  - Pass the signaling channel to `Membrane.WebRTC.Source` or `Membrane.WebRTC.Sink` (this
    can also be done before the call to `register_peer/2`).
  - Send and receive signaling messages. Messages can be sent by calling `signal/2`.
    The channel sends `t:message/0` to the peer.
  """
  use GenServer

  require Logger

  alias ExWebRTC.{ICECandidate, SessionDescription}

  @enforce_keys [:pid]
  defstruct @enforce_keys

  @type t :: %__MODULE__{pid: pid()}

  @typedoc """
  Messages sent by the signaling channel to the peer.
  """
  @type message :: {__MODULE__, pid(), message_content, metadata :: map}

  @typedoc """
  Messages that the peer sends with `signal/2` and receives in `t:message/0`.

  If the `message_format` of the peer is `ex_webrtc` (default), they should be
  `t:ex_webrtc_message/0`.
  If the `message_format` is `json_data`, they should be `t:json_data_message/0`.

  The `message_format` of the peer can be set in `register_peer/2`.
  """
  @type message_content :: ex_webrtc_message | json_data_message

  @typedoc """
  Messages sent and received if `message_format` is `ex_webrtc`.
  """
  @type ex_webrtc_message :: ICECandidate.t() | SessionDescription.t()

  @typedoc """
  Messages sent and received if `message_format` is `json_data`.

  The keys and values are the following
  - `%{"type" => "sdp_offer", "data" => data}`, where data is the return value of
    `ExWebRTC.SessionDescription.to_json/1` or `RTCPeerConnection.create_offer` in the JavaScript API
  - `%{"type" => "sdp_answer", "data" => data}`, where data is the return value of
    `ExWebRTC.SessionDescription.to_json/1` or `RTCPeerConnection.create_answer` in the JavaScript API
  - `%{"type" => "ice_candidate", "data" => data}`, where data is the return value of
    `ExWebRTC.ICECandidate.to_json/1` or `event.candidate` from the `RTCPeerConnection.onicecandidate`
    callback in the JavaScript API.
  """
  @type json_data_message :: %{String.t() => term}

  @spec new() :: t
  def new() do
    {:ok, pid} = GenServer.start_link(__MODULE__, [])
    %__MODULE__{pid: pid}
  end

  @doc """
  Registers a process as a peer, so that it can send and receive signaling messages.

  Options:
  - `pid` - pid of the peer, `self()` by default
  - `message_format` - `:ex_webrtc` by default, see `t:message_content/0`

  See the moduledoc for details.
  """
  @spec register_peer(t, message_format: :ex_webrtc | :json_data, pid: pid) :: :ok
  def register_peer(%__MODULE__{pid: pid}, opts \\ []) do
    opts =
      opts
      |> Keyword.validate!(message_format: :ex_webrtc, pid: self())
      |> Map.new()
      |> Map.put(:is_element, false)

    GenServer.call(pid, {:register_peer, opts})
  end

  @doc false
  @spec register_element(t) :: :ok
  def register_element(%__MODULE__{pid: pid}) do
    GenServer.call(
      pid,
      {:register_peer, %{pid: self(), message_format: :ex_webrtc, is_element: true}}
    )
  end

  @doc """
  Sends a signaling message to the channel.

  The calling process must be previously registered with `register_peer/2`.
  See the moduledoc for details.
  """
  @spec signal(t, message_content, metadata :: map) :: :ok
  def signal(%__MODULE__{pid: pid}, message, metadata \\ %{}) do
    send(pid, {:signal, self(), message, metadata})
    :ok
  end

  @spec close(t) :: :ok
  def close(%__MODULE__{pid: pid}) do
    GenServer.stop(pid)
  end

  @impl true
  def init(_opts) do
    state = %{
      peer_a: nil,
      peer_b: nil,
      message_queue: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register_peer, peer}, _from, state) do
    Process.monitor(peer.pid)

    case state do
      %{peer_a: nil} ->
        {:reply, :ok, %{state | peer_a: peer}}

      %{peer_b: nil, message_queue: queue} ->
        state = %{state | peer_b: peer}

        queue
        |> Enum.reverse()
        |> Enum.each(fn {message, metadata} ->
          send_peer(state.peer_a, state.peer_b, message, metadata)
        end)

        {:reply, :ok, %{state | message_queue: []}}

      state ->
        raise """
        Cannot register a peer, both peers already registered: \
        #{inspect(state.peer_a.pid)}, #{inspect(state.peer_b.pid)}
        """
    end
  end

  @impl true
  def handle_info({:signal, _from_pid, message, metadata}, %{peer_b: nil} = state) do
    {:noreply, %{state | message_queue: [{message, metadata} | state.message_queue]}}
  end

  @impl true
  def handle_info({:signal, from_pid, message, metadata}, state) do
    {from_peer, to_peer} = get_peers(from_pid, state)
    send_peer(from_peer, to_peer, message, metadata)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, pid, reason}, state) do
    {peer, _other_peer} = get_peers(pid, state)
    reason = if peer.is_element, do: reason, else: :normal
    {:stop, reason, state}
  end

  defp get_peers(pid, state) do
    case state do
      %{peer_a: %{pid: ^pid} = peer_a, peer_b: peer_b} -> {peer_a, peer_b}
      %{peer_a: peer_a, peer_b: %{pid: ^pid} = peer_b} -> {peer_b, peer_a}
    end
  end

  defp send_peer(
         %{message_format: format},
         %{message_format: format, pid: pid},
         message,
         metadata
       ) do
    send(pid, {__MODULE__, self(), message, metadata})
  end

  defp send_peer(
         %{message_format: :ex_webrtc},
         %{message_format: :json_data, pid: pid},
         message,
         metadata
       ) do
    json_data =
      case message do
        %ICECandidate{} ->
          %{"type" => "ice_candidate", "data" => ICECandidate.to_json(message)}

        %SessionDescription{type: type} ->
          %{"type" => "sdp_#{type}", "data" => SessionDescription.to_json(message)}
      end

    send(pid, {__MODULE__, self(), json_data, metadata})
  end

  defp send_peer(
         %{message_format: :json_data},
         %{message_format: :ex_webrtc, pid: pid},
         message,
         metadata
       ) do
    message =
      case message do
        %{"type" => "ice_candidate", "data" => candidate} -> ICECandidate.from_json(candidate)
        %{"type" => "sdp_offer", "data" => offer} -> SessionDescription.from_json(offer)
        %{"type" => "sdp_answer", "data" => answer} -> SessionDescription.from_json(answer)
      end

    send(pid, {__MODULE__, self(), message, metadata})
  end
end
