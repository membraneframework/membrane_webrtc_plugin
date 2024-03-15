defmodule Membrane.WebRTC.Source do
  use Membrane.Bin

  alias Membrane.WebRTC.ExWebRTCSource

  def_options signaling: [],
              video_codec: [default: :vp8],
              depayload_rtp: [default: true]

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request,
    options: [kind: [default: nil]]

  @impl true
  def handle_init(_ctx, opts) do
    {signaling, opts} = opts |> Map.from_struct() |> Map.pop!(:signaling)
    spec = child(:webrtc, %ExWebRTCSource{signaling: signaling, video_codec: opts.video_codec})
    state = %{tracks: %{}} |> Map.merge(opts)
    {[spec: spec], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, pad_id) = pad_ref, ctx, state) do
    %{kind: kind} = ctx.pad_options
    track = state.tracks[pad_id]

    if ctx.playback == :stopped and kind == nil do
      raise "Option `kind` not specified for pad #{inspect(pad_ref)}"
    end

    if ctx.playback == :playing and track == nil do
      raise "Unknown track id #{inspect(pad_id)}, cannot link pad #{inspect(pad_ref)}"
    end

    kind = kind || track.kind

    spec =
      if state.depayload_rtp do
        get_child(:webrtc)
        |> via_out(pad_ref, options: [kind: kind])
        |> child(get_depayloader(kind, state))
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

  defp get_depayloader(:audio, _state) do
    %Membrane.RTP.DepayloaderBin{depayloader: Membrane.RTP.Opus.Depayloader, clock_rate: 48_000}
  end

  defp get_depayloader(:video, %{video_codec: :vp8}) do
    %Membrane.RTP.DepayloaderBin{depayloader: Membrane.RTP.VP8.Depayloader, clock_rate: 96_000}
  end

  defp get_depayloader(:video, %{video_codec: :h264}) do
    %Membrane.RTP.DepayloaderBin{depayloader: Membrane.RTP.H264.Depayloader, clock_rate: 96_000}
  end
end
