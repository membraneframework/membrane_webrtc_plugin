defmodule Membrane.WebRTC.Sink do
  use Membrane.Bin

  alias Membrane.WebRTC.ExWebRTCSink

  def_options signaling_channel: [], tracks: [], payload_rtp: [default: true]

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request,
    options: [kind: [], payload_rtp: [default: true]]

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      child(:webrtc, %ExWebRTCSink{
        signaling_channel: opts.signaling_channel,
        tracks: opts.tracks
      })

    {[spec: spec], %{tracks: %{}, payload_rtp: opts.payload_rtp}}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, _id) = pad_ref, ctx, state) do
    %{kind: kind} = ctx.pad_options

    spec =
      if state.payload_rtp do
        bin_input(pad_ref)
        |> child(get_payloader(kind))
        |> via_in(pad_ref, options: [kind: kind])
        |> get_child(:webrtc)
      else
        bin_input(pad_ref)
        |> via_in(pad_ref, options: [kind: kind])
        |> get_child(:webrtc)
      end

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(:connected, :webrtc, _ctx, state) do
    {[setup: :complete], state}
  end

  defp get_payloader(:audio) do
    Membrane.RTP.Opus.Payloader
  end

  defp get_payloader(:video) do
    Membrane.RTP.H264.Payloader
  end
end
