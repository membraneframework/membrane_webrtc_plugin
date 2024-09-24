defmodule Membrane.WebRTC.WhipServer do
  @moduledoc """
  Server accepting WHIP connections.

  Accepts the following options:

  - `handle_new_client` - function that accepts the client token and returns either
    the signaling channel to negotiate the connection or error to reject it. The signaling
    channel can be passed to `Membrane.WebRTC.Source`.
  - `serve_static` - path to static assets that should be served along with WHIP,
    useful to serve HTML assets. If set to `false` (default), no static assets are
    served
  - Any of `t:Bandit.options/0` - Bandit configuration
  """

  alias Membrane.WebRTC.SignalingChannel

  @type option ::
          {:handle_new_client,
           (token :: String.t() -> {:ok, SignalingChannel.t()} | {:error, reason :: term()})}
          | {:serve_static, String.t() | false}
          | {atom, term()}
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    Bandit.child_spec(bandit_opts(opts))
  end

  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts) do
    Bandit.start_link(bandit_opts(opts))
  end

  defp bandit_opts(opts) do
    {whip_opts, bandit_opts} = Keyword.split(opts, [:handle_new_client, :serve_static])
    plug = {__MODULE__.Router, whip_opts}
    [plug: plug] ++ bandit_opts
  end

  defmodule Router do
    @moduledoc """
    WHIP router pluggable to a plug pipeline.

    Accepts the same options as `Membrane.WebRTC.WhipServer`.

    ## Example

    ```
    defmodule Router do
      use Plug.Router

      plug(Plug.Logger)
      plug(Plug.Static, at: "/static", from: "assets")
      plug(:match)
      plug(:dispatch)

      forward(
        "/whip",
        to: Membrane.WebRTC.WhipServer.Router,
        handle_new_client: &__MODULE__.handle_new_client/1
      )

      def handle_new_client(token) do
        validate_token!(token)
        signaling = Membrane.WebRTC.SignalingChannel.new()
        # pass the signaling channel to a pipeline
        {:ok, signaling}
      end
    end

    Bandit.start_link(plug: Router, ip: any)
    ```
    """
    use Plug.Router

    plug(Plug.Logger, log: :info)
    plug(Corsica, origins: "*")
    plug(:match)
    plug(:dispatch)

    # TODO: the HTTP response codes are not completely compliant with the RFCs

    defmodule ClientHandler do
      @moduledoc false
      use GenServer

      @spec start_link(GenServer.options()) :: {:ok, pid()}
      def start_link(opts), do: GenServer.start_link(__MODULE__, [], opts)

      @spec exec(GenServer.server(), (state -> {resp, state})) :: resp
            when state: term(), resp: term()
      def exec(client_handler, fun), do: GenServer.call(client_handler, {:exec, fun})
      @spec stop(GenServer.server()) :: :ok
      def stop(client_handler), do: GenServer.stop(client_handler)

      @impl true
      def init(_opts), do: {:ok, nil}

      @impl true
      def handle_call({:exec, fun}, _from, state) do
        {reply, state} = fun.(state)
        {:reply, reply, state}
      end

      @impl true
      def handle_info(_message, state), do: {:noreply, state}
    end

    post "/" do
      with {:ok, token} <- get_token(conn),
           {:ok, offer_sdp, conn} <- get_body(conn, "application/sdp"),
           resource_id = generate_resource_id(),
           {:ok, client_handler} = ClientHandler.start_link(name: handler_name(resource_id)),
           {:ok, answer_sdp} <-
             get_answer(client_handler, offer_sdp, token, conn.private.whip.handle_new_client) do
        Process.unlink(client_handler)

        conn
        |> put_resp_header("location", Path.join(conn.request_path, "resource/#{resource_id}"))
        |> put_resp_content_type("application/sdp")
        |> resp(201, answer_sdp)
      else
        {:error, _other} -> resp(conn, 400, "Bad request")
      end
      |> send_resp()
    end

    patch "resource/:resource_id" do
      with {:ok, sdp, conn} <- get_body(conn, "application/trickle-ice-sdpfrag"),
           sdp = ExSDP.parse!(sdp),
           media = List.first(sdp.media),
           {"candidate", candidate} <- ExSDP.get_attribute(media, "candidate") || :no_candidate do
        {:ice_ufrag, ufrag} = ExSDP.get_attribute(sdp, :ice_ufrag)
        {:mid, mid} = ExSDP.get_attribute(media, :mid)

        candidate = %ExWebRTC.ICECandidate{
          candidate: candidate,
          sdp_mid: mid,
          username_fragment: ufrag,
          sdp_m_line_index: 0
        }

        ClientHandler.exec(handler_name(resource_id), fn signaling ->
          SignalingChannel.signal(signaling, candidate)
          {:ok, signaling}
        end)

        resp(conn, 204, "")
      else
        :no_candidate -> resp(conn, 204, "")
        {:error, _res} -> resp(conn, 400, "Bad request")
      end
      |> send_resp()
    end

    delete "resource/:resource_id" do
      ClientHandler.stop(handler_name(resource_id))
      send_resp(conn, 204, "")
    end

    get "static/*_" do
      case conn.private.whip.plug_static do
        nil -> send_resp(conn, 404, "Not found")
        plug_static -> Plug.Static.call(conn, plug_static)
      end
    end

    match _ do
      send_resp(conn, 404, "Not found")
    end

    @impl true
    def init(opts) do
      {handle_new_client, opts} = Keyword.pop(opts, :handle_new_client)
      unless handle_new_client, do: raise("Missing option 'handle_new_client'")
      {serve_static, opts} = Keyword.pop(opts, :serve_static, false)
      if opts != [], do: raise("Unknown options: #{Enum.join(opts, ", ")}")

      plug_static =
        if serve_static, do: Plug.Static.init(at: "static", from: serve_static)

      super(%{handle_new_client: handle_new_client, plug_static: plug_static})
    end

    @impl true
    def call(conn, opts) do
      conn
      |> put_private(:whip, opts)
      |> super(opts)
    end

    defp get_token(conn) do
      with ["Bearer " <> token] <- get_req_header(conn, "authorization") do
        {:ok, token}
      else
        _other -> {:error, :unauthorized}
      end
    end

    defp get_body(conn, content_type) do
      with [^content_type] <- get_req_header(conn, "content-type"),
           {:ok, body, conn} <- read_body(conn) do
        {:ok, body, conn}
      else
        headers when is_list(headers) -> {:error, :unsupported_media}
        _other -> {:error, :bad_request}
      end
    end

    defp get_answer(client_handler, offer_sdp, token, handle_new_client) do
      ClientHandler.exec(client_handler, fn _state ->
        with {:ok, signaling} <- handle_new_client.(token) do
          SignalingChannel.register_peer(signaling)

          SignalingChannel.signal(
            signaling,
            %ExWebRTC.SessionDescription{type: :offer, sdp: offer_sdp},
            %{candidates_in_sdp: true}
          )

          receive do
            {SignalingChannel, _pid, answer, _metadata} ->
              %ExWebRTC.SessionDescription{type: :answer, sdp: answer_sdp} = answer
              {{:ok, answer_sdp}, signaling}
          after
            5000 -> raise "Timeout waiting for SDP answer"
          end
        else
          {:error, reason} -> {{:error, reason}, nil}
        end
      end)
    end

    defp generate_resource_id() do
      for _ <- 1..10, into: "", do: <<Enum.random(~c"0123456789abcdef")>>
    end

    defp handler_name(resource_id) do
      {:via, Registry, {Membrane.WebRTC.WhipRegistry, resource_id}}
    end
  end
end
