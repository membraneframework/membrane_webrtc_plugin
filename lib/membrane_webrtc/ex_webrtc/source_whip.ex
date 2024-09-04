defmodule Membrane.WebRTC.ExWebRTCSourceWHIP do
  @moduledoc false

  use Membrane.Source

  require Membrane.Logger

  alias Membrane.WebRTC.WhipWhep.{PeerSupervisor, Forwarder, Router}
  alias Membrane.WebRTC.ExWebRTCUtils
  def_options whip: [], video_codec: [], port: [], ip: [], parent: []

  def_output_pad :output,
    accepted_format: Membrane.RTP,
    availability: :on_request,
    flow_control: :push,
    options: [kind: [default: nil]]

  @impl true
  def handle_init(_ctx, opts) do
    self = self()

    children = [
      {Bandit,
       plug: Router, scheme: :http, ip: ExWebRTCUtils.parse_ip_to_tuple(opts.ip), port: opts.port},
      PeerSupervisor,
      {Forwarder, source_pid: self},
      {Registry, name: __MODULE__.PeerRegistry, keys: :unique}
    ]

    Supervisor.start_link(children, strategy: :one_for_all, name: __MODULE__.Supervisor)

    {[],
     %{
       output_tracks: %{},
       parent: opts.parent
     }}
  end

  @impl true
  def handle_playing(_ctx, state) do
    IO.inspect("source whip PLAYING")
    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_info(:peer_connected, _ctx, state) do
    IO.inspect("source whip handle_info peer_connected")
    {[setup: :complete, notify_parent: :setup_complete], state}
  end

  @impl true
  def handle_info({_x, _y, _z}, %{playback: :stopped} = _ctx, state) do
    # IO.inspect("source whip handle_info playback stopped")
    {[], state}
  end

  @impl true
  def handle_info({:video_packet, id, packet}, _ctx, state) do
    buffer = %Membrane.Buffer{
      payload: packet.payload,
      metadata: %{rtp: packet |> Map.from_struct() |> Map.delete(:payload)}
    }

    {[buffer: {state.output_tracks[id], buffer}], state}
  end

  @impl true
  def handle_info({:audio_packet, id, packet}, _ctx, state) do
    buffer = %Membrane.Buffer{
      payload: packet.payload,
      metadata: %{rtp: packet |> Map.from_struct() |> Map.delete(:payload)}
    }

    {[buffer: {state.output_tracks[id], buffer}], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, pad_id) = pad, _ctx, state) do
    %{output_tracks: output_tracks} = state
    output_tracks = Map.put(output_tracks, pad_id, pad)
    state = %{state | output_tracks: output_tracks}
    IO.inspect(state, label: "source whip pad added")
    {[stream_format: {pad, %Membrane.RTP{}}], state}
  end
end
