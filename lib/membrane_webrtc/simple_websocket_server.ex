defmodule Membrane.WebRTC.SimpleWebSocketServer do
  @moduledoc """
  A simple WebSocket server spawned by `Membrane.WebRTC.Source`
  and `Membrane.WebRTC.Sink`. It accepts a single connection
  and passes the messages between the client and a Membrane
  element.

  The messages sent and received by the server are JSON-encoded
  `t:Membrane.WebRTC.Signaling.json_data_message/0`.
  Additionally, the server sends a `{type: "keep_alive", data: ""}`
  messages to prevent the WebSocket from being closed.

  Examples of configuring and interacting with the server can
  be found in the `examples` directory.
  """

  alias Membrane.WebRTC.Signaling

  @typedoc """
  Options for the server.

  The port is required, while the IP address defaults to `{127, 0, 0, 1}`.
  """
  @type options :: [ip: :inet.ip_address(), port: :inet.port_number()]

  @doc false
  @spec child_spec({options, Signaling.t()}) :: Supervisor.child_spec()
  def child_spec({opts, signaling}) do
    opts = opts |> validate_options!() |> Map.new()

    Supervisor.child_spec(
      {Bandit,
       plug: {__MODULE__.Router, %{conn_cnt: :atomics.new(1, []), signaling: signaling}},
       ip: opts.ip,
       port: opts.port},
      []
    )
  end

  @spec validate_options!(options()) :: options() | no_return()
  def validate_options!(options), do: Keyword.validate!(options, [:port, ip: {127, 0, 0, 1}])

  @doc false
  @spec start_link_supervised(pid, options) :: Signaling.t()
  def start_link_supervised(utility_supervisor, opts) do
    signaling = Signaling.new()

    {:ok, _pid} =
      Membrane.UtilitySupervisor.start_link_child(
        utility_supervisor,
        {__MODULE__, {opts, signaling}}
      )

    signaling
  end

  defmodule Router do
    @moduledoc false
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get "/" do
      conn_cnt = :atomics.add_get(conn.private.conn_cnt, 1, 1)

      if conn_cnt == 1 do
        WebSockAdapter.upgrade(
          conn,
          Membrane.WebRTC.SimpleWebSocketServer.PeerHandler,
          %{signaling: conn.private.signaling},
          []
        )
      else
        send_resp(conn, 429, "already connected")
      end
    end

    match _ do
      send_resp(conn, 404, "not found")
    end

    @impl true
    def call(conn, opts) do
      conn
      |> put_private(:conn_cnt, opts.conn_cnt)
      |> put_private(:signaling, opts.signaling)
      |> super(opts)
    end
  end

  defmodule PeerHandler do
    @moduledoc false

    @behaviour WebSock

    require Logger

    alias Membrane.WebRTC.Signaling

    @impl true
    def init(opts) do
      Signaling.register_peer(opts.signaling, message_format: :json_data)
      Process.send_after(self(), :keep_alive, 30_000)
      {:ok, %{signaling: opts.signaling}}
    end

    @impl true
    def handle_in({message, opcode: :text}, state) do
      Signaling.signal(state.signaling, Jason.decode!(message))
      {:ok, state}
    end

    @impl true
    def handle_info({:membrane_webrtc_signaling, _pid, message, _metadata}, state) do
      {:push, {:text, Jason.encode!(message)}, state}
    end

    @impl true
    def handle_info(:keep_alive, state) do
      Process.send_after(self(), :keep_alive, 30_000)
      {:push, {:text, Jason.encode!(%{type: "keep_alive", data: ""})}, state}
    end

    @impl true
    def handle_info(message, state) do
      Logger.debug(
        "#{inspect(__MODULE__)} process ignores unsupported message #{inspect(message)}"
      )

      {:ok, state}
    end
  end
end
