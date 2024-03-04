defmodule Membrane.WebRTC.Source do
  use Membrane.Bin

  alias Membrane.WebRTC.ExWebRTCSource

  def_options signaling_channel: []

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request,
    options: [depayload_rtp: [default: true]]

  @impl true
  def handle_init(_ctx, opts) do
    spec = child(:webrtc, %ExWebRTCSource{signaling_channel: opts.signaling_channel})
    {[spec: spec], %{tracks: %{}}}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[setup: :incomplete], state}
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
  def handle_child_notification(:ready, :webrtc, _ctx, state) do
    {[setup: :complete], state}
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
