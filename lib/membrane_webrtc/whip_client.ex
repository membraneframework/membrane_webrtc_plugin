defmodule Membrane.WebRTC.WhipClient do
  @moduledoc """
  WebRTC WHIP Client.

  Accepts the following options:
  - `uri` - address of a WHIP server
  - `signaling` - the signaling channel - pass the same signaling channel to `Membrane.WebRTC.Sink`
    to connect it with the WHIP client
  - `token` - token to authenticate in the server, defaults to an empty string
  """
  use GenServer

  require Logger

  alias ExWebRTC.{ICECandidate, SessionDescription}
  alias Membrane.WebRTC.Signaling

  @spec start_link([
          {:signaling, Signaling.t()} | {:uri, String.t()} | {:token, String.t()}
        ]) ::
          {:ok, pid()}
  def start_link(opts) do
    enforce_keys = [:signaling, :uri]
    opts = Keyword.validate!(opts, enforce_keys ++ [token: ""]) |> Map.new()
    missing_keys = Enum.reject(enforce_keys, &is_map_key(opts, &1))

    unless missing_keys == [],
      do: raise(ArgumentError, "Missing option #{Enum.join(missing_keys, ", ")}")

    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    Signaling.register_peer(opts.signaling)
    Process.monitor(opts.signaling.pid)
    {:ok, Map.merge(opts, %{resource_uri: nil})}
  end

  @impl true
  def handle_info(
        {Signaling, pid, %SessionDescription{type: :offer, sdp: offer_sdp}, _metadata},
        %{signaling: signaling} = state
      )
      when signaling.pid == pid do
    resp =
      Req.post!(state.uri,
        headers: [
          Accept: "application/sdp",
          "Content-Type": "application/sdp",
          authorization: "Bearer #{state.token}"
        ],
        body: offer_sdp
      )

    %Req.Response{status: status, body: answer_sdp} = resp
    unless status in 200..299, do: raise("Invalid WHIP answer response status: #{status}")

    resource_id =
      case Req.Response.get_header(resp, "location") do
        [resource_id] -> resource_id
        _other -> raise "Invalid WHEP answer location header"
      end

    resource_uri = URI.parse(state.uri) |> then(&%URI{&1 | path: resource_id}) |> URI.to_string()

    pid = self()

    Task.start(fn ->
      monitor = Process.monitor(pid)

      receive do
        {:DOWN, ^monitor, _pid, _type, _reason} -> :ok
      end

      %Req.Response{status: status} = Req.delete!(resource_uri)

      unless status in 200..299,
        do: Logger.warning("Failed to send delete request to #{resource_uri}")
    end)

    Signaling.signal(signaling, %SessionDescription{type: :answer, sdp: answer_sdp})
    {:noreply, %{state | resource_uri: resource_uri}}
  end

  @impl true
  def handle_info(
        {Signaling, pid, %ICECandidate{} = candidate, _metadata},
        %{signaling: signaling} = state
      )
      when signaling.pid == pid do
    # It's not necessarily the mline that was in the SDP
    # but it shouldn't matter
    media =
      ExSDP.Media.new(:audio, 9, "UDP/TLS/RTP/SAVPF", 0)
      |> ExSDP.add_attribute({"candidate", candidate.candidate})
      |> ExSDP.add_attribute({:mid, candidate.sdp_mid})

    sdp =
      ExSDP.new()
      |> ExSDP.add_media(media)
      |> ExSDP.add_attribute({:ice_ufrag, candidate.username_fragment})

    %Req.Response{status: status} =
      Req.patch!(state.resource_uri,
        headers: ["Content-Type": "application/trickle-ice-sdpfrag"],
        body: to_string(sdp)
      )

    unless status in 200..299,
      do: Logger.error("Failed to send candindate to #{state.resource_uri}")

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:DOWN, _monitor, _type, pid, _reason},
        %{signaling: %Signaling{pid: pid}} = state
      ) do
    {:stop, :normal, state}
  end
end
