defmodule Membrane.WebRTC.WhipServer do
  def child_spec(opts) do
    Bandit.child_spec(bandit_opts(opts))
  end

  def start_link(opts) do
    Bandit.start_link(bandit_opts(opts))
  end

  defp bandit_opts(opts) do
    opts =
      opts |> Keyword.validate!([:handle_new_client, :port, ip: {0, 0, 0, 0}]) |> Map.new()

    [
      plug: {__MODULE__.Router, %{handle_new_client: opts.handle_new_client}},
      scheme: :http,
      ip: opts.ip,
      port: opts.port
    ]
  end

  defmodule Router do
    use Plug.Router

    alias Membrane.WebRTC.SignalingChannel

    plug(Plug.Logger)
    plug(Corsica, origins: "*")
    plug(:match)
    plug(:dispatch)
    # TODO: the HTTP responses are not completely compliant with the RFCs

    defmodule ClientHandler do
      @moduledoc false
      use GenServer

      def start_link(opts), do: GenServer.start_link(__MODULE__, [], opts)
      def exec(client_handler, fun), do: GenServer.call(client_handler, {:exec, fun})
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
             get_answer(client_handler, offer_sdp, token, conn.private.handle_new_client) do
        Process.unlink(client_handler)

        conn
        |> put_resp_header("location", "#{conn.request_path}resource/#{resource_id}")
        |> put_resp_content_type("application/sdp")
        |> resp(201, answer_sdp)
      else
        {:error, _other} -> resp(conn, 400, "Bad request")
      end
      |> send_resp()
    end

    patch "resource/:resource_id" do
      case get_body(conn, "application/trickle-ice-sdpfrag") do
        {:ok, body, conn} ->
          # TODO: this is not compliant with the RFC
          candidate =
            body
            |> Jason.decode!()
            |> ExWebRTC.ICECandidate.from_json()

          ClientHandler.exec(handler_name(resource_id), fn signaling ->
            SignalingChannel.signal(signaling, candidate)
            {:ok, signaling}
          end)

          resp(conn, 204, "")

        {:error, _res} ->
          resp(conn, 400, "Bad request")
      end
      |> send_resp()
    end

    delete "resource/:resource_id" do
      ClientHandler.stop(handler_name(resource_id))
      send_resp(conn, 204, "")
    end

    match _ do
      send_resp(conn, 404, "Not found")
    end

    @impl true
    def call(conn, opts) do
      conn
      |> put_private(:handle_new_client, opts.handle_new_client)
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
