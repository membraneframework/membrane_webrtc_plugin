# this module is a simple http server needed to negotiate sdp with whip peer

defmodule Membrane.WebRTC.WhipWhep.Router do
  use Plug.Router

  alias Membrane.WebRTC.WhipWhep.{Forwarder, PeerSupervisor}

  @token "example"

  plug(Plug.Logger)
  plug(Corsica, origins: "*")
  plug(:match)
  plug(:dispatch)

  post "/whip" do
    with :ok <- authenticate(conn),
         {:ok, offer_sdp, conn} <- get_body(conn, "application/sdp"),
         {:ok, pc, pc_id, answer_sdp} <- PeerSupervisor.start_whip(offer_sdp),
         :ok <- Forwarder.connect_input(pc) do
      conn
      |> put_resp_header("location", "/resource/#{pc_id}")
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      {:error, _other} -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp authenticate(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- token == @token do
      :ok
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
end
