defmodule Membrane.WebRTC.Source do
  use Membrane.Bin

  alias Membrane.WebRTC.{ExWebRTCSource, SignalingChannel, SimpleWebSocketServer}

  def_options signaling_channel: []

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request,
    options: [depayload_rtp: [default: true]]

  @impl true
  def handle_setup(ctx, opts) do
    actions =
      case opts.signaling_channel do
        %SignalingChannel{} = signaling ->
          [spec: child(:webrtc, %ExWebRTCSource{signaling_channel: signaling})]

        {:websocket, opts} ->
          # Membrane.UtilitySupervisor.start_link_child(
          #   ctx.utility_supervisor,
          #   {SimpleWebSocketServer, [element: self()] ++ opts}
          # )

          SimpleWebSocketServer.start_link([element: self()] ++ opts)

          [setup: :incomplete]
      end

    {actions, %{tracks: %{}}}
  end

  @impl true
  def handle_info({:signaling, signaling}, _ctx, state) do
    {[spec: child(:webrtc, %ExWebRTCSource{signaling_channel: signaling}), setup: :complete],
     state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, id) = pad_ref, ctx, state) do
    kind =
      cond do
        id in [:audio, :video] -> id
        track = state.tracks[id] -> track.kind
        true -> raise ArgumentError
      end

    spec =
      if ctx.pad_options.depayload_rtp do
        get_child(:webrtc)
        |> via_out(pad_ref)
        |> child(get_depayloader(kind))
        |> bin_output(pad_ref)
      else
        get_child(:webrtc) |> via_out(pad_ref) |> bin_output(pad_ref)
      end

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:new_track, track}, :webrtc, _ctx, state) do
    state = put_in(state, [:tracks, track.id], track)
    {[notify_parent: {:new_track, track}], state}
  end

  defp get_depayloader(:audio) do
    %Membrane.RTP.DepayloaderBin{depayloader: Membrane.RTP.Opus.Depayloader, clock_rate: 48_000}
  end

  defp get_depayloader(:video) do
    %Membrane.RTP.DepayloaderBin{depayloader: Membrane.RTP.H264.Depayloader, clock_rate: 96_000}
  end
end
