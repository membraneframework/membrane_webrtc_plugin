defmodule Membrane.WebRTC.Sink do
  use Membrane.Bin

  alias Membrane.WebRTC.ExWebRTCSink

  def_options signaling: [],
              tracks: [default: [:audio, :video]],
              payload_rtp: [default: true],
              video_codec: [default: :vp8]

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
        signaling: opts.signaling,
        tracks: opts.tracks,
        video_codec: opts.video_codec
      })

    {[spec: spec], %{tracks: %{}, payload_rtp: opts.payload_rtp, video_codec: opts.video_codec}}
  end

  @impl true
  def handle_setup(_ctx, state) do
    {[setup: :incomplete], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, _pid) = pad_ref, ctx, state) do
    %{kind: kind} = ctx.pad_options

    spec =
      if state.payload_rtp do
        bin_input(pad_ref)
        |> child(get_payloader(kind, state))
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

  @impl true
  def handle_element_end_of_stream(:webrtc, Pad.ref(:input, id), _ctx, state) do
    {[notify_parent: {:end_of_stream, id}], state}
  end

  @impl true
  def handle_element_end_of_stream(_name, _pad, _ctx, state) do
    {[], state}
  end

  defp get_payloader(:audio, _state), do: Membrane.RTP.Opus.Payloader

  defp get_payloader(:video, %{video_codec: :h264}),
    do: %Membrane.RTP.H264.Payloader{max_payload_size: 1000}

  defp get_payloader(:video, %{video_codec: :vp8}), do: Membrane.RTP.VP8.Payloader
end
