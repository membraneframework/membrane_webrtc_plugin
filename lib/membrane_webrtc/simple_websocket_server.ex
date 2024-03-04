defmodule Membrane.WebRTC.SimpleWebSocketServer do
  def child_spec(opts) do
    Supervisor.child_spec(
      {Bandit,
       plug: {__MODULE__.Router, %{conn_cnt: :atomics.new(1, []), element: opts[:element]}},
       ip: opts[:ip] || {127, 0, 0, 1},
       port: opts[:port]},
      []
    )
  end

  defmodule Router do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    plug(Plug.Static, at: "/", from: "assets")

    get "/ws" do
      conn_cnt = :atomics.add_get(conn.private.conn_cnt, 1, 1)

      if conn_cnt == 1 do
        WebSockAdapter.upgrade(
          conn,
          Membrane.WebRTC.SimpleWebSocketServer.PeerHandler,
          %{element: conn.private.element},
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
      |> put_private(:element, opts.element)
      |> super(opts)
    end
  end

  defmodule PeerHandler do
    @behaviour WebSock

    alias ExWebRTC.{ICECandidate, SessionDescription}
    alias Membrane.WebRTC.SignalingChannel

    @impl true
    def init(opts) do
      signaling = SignalingChannel.new(:json_data)
      send(opts.element, {:signaling, signaling})
      {:ok, %{signaling: signaling}}
    end

    @impl true
    def handle_in({message, opcode: :text}, state) do
      SignalingChannel.signal(state.signaling, Jason.decode!(message))
      {:ok, state}
    end

    @impl true
    def handle_info({SignalingChannel, message}, state) do
      {:push, {:text, Jason.encode!(message)}, state}
    end
  end
end
