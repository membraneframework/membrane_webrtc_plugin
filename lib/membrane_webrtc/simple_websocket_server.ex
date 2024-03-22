defmodule Membrane.WebRTC.SimpleWebSocketServer do
  @moduledoc false

  alias Membrane.WebRTC.SignalingChannel

  @type option :: {:ip, :inet.ip_address()} | {:port, :inet.port_number()}

  @spec child_spec([option | {:signaling, SignalingChannel.t()}]) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts = opts |> Keyword.validate!([:signaling, :port, ip: {127, 0, 0, 1}]) |> Map.new()

    Supervisor.child_spec(
      {Bandit,
       plug: {__MODULE__.Router, %{conn_cnt: :atomics.new(1, []), signaling: opts.signaling}},
       ip: opts.ip,
       port: opts.port},
      []
    )
  end

  @spec start_link_supervised(pid, [option]) :: SignalingChannel.t()
  def start_link_supervised(utility_supervisor, opts) do
    signaling = SignalingChannel.new()
    opts = [signaling: signaling] ++ opts

    {:ok, _pid} =
      Membrane.UtilitySupervisor.start_link_child(utility_supervisor, {__MODULE__, opts})

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

    alias Membrane.WebRTC.SignalingChannel

    @impl true
    def init(opts) do
      SignalingChannel.register_peer(opts.signaling, message_format: :json_data)
      Process.send_after(self(), :ping, 30_000)
      {:ok, %{signaling: opts.signaling}}
    end

    @impl true
    def handle_in({message, opcode: :text}, state) do
      SignalingChannel.signal(state.signaling, Jason.decode!(message))
      {:ok, state}
    end

    @impl true
    def handle_info({SignalingChannel, _pid, message}, state) do
      {:push, {:text, Jason.encode!(message)}, state}
    end

    @impl true
    def handle_info(:ping, state) do
      Process.send_after(self(), :ping, 30_000)
      {:push, {:text, Jason.encode!(%{type: "ping", data: ""})}, state}
    end

    @impl true
    def handle_info(message, state) do
      Logger.debug("Ignoring unsupported message #{inspect(message)}")
      {:ok, state}
    end
  end
end
