defmodule Membrane.WebRTC.ExWebRTCSourceWHIP do
  @moduledoc false

  use Membrane.Source

  require Membrane.Logger

  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}
  alias Membrane.WebRTC.{ExWebRTCUtils, SignalingChannel, SimpleWebSocketServer, Router}

  def_options whip: [], video_codec: [], ice_servers: []

  def_output_pad :output,
    accepted_format: Membrane.RTP,
    availability: :on_request,
    flow_control: :push,
    options: [kind: [default: nil]]

  @impl true
  def handle_init(_ctx, opts) do
    # here run http server waiting for /whip request to negotiate connection
    children = [
      {Bandit, plug: Router, scheme: :http, ip: {127, 0, 0, 1}, port: 8888},
      {Registry, name: __MODULE__.PeerRegistry, keys: :unique}
    ]

    Supervisor.start_link(children, strategy: :one_for_all, name: __MODULE__.Supervisor)

    Process.sleep(10_000)
    {[],
     %{
       pc: nil,
       output_tracks: %{},
       awaiting_outputs: [],
       awaiting_candidates: [],
       status: :init,
       audio_params: ExWebRTCUtils.codec_params(:opus),
       video_params: ExWebRTCUtils.codec_params(opts.video_codec),
       ice_servers: opts.ice_servers
     }}
  end

  @impl true
  def handle_setup(_ctx, state) do

    {[setup: :incomplete], state}
  end


end
