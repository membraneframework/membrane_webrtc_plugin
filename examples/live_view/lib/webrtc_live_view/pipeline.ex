defmodule WebRTCLiveView.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    spec =
      child(:webrtc_source, %Membrane.WebRTC.Source{
        allowed_video_codecs: :vp8,
        signaling: opts[:ingress_signaling]
      })
      |> via_out(:output, options: [kind: :video])
      |> via_in(:input, options: [kind: :video])
      |> child(:webrtc_sink, %Membrane.WebRTC.Sink{
        video_codec: :vp8,
        signaling: opts[:egress_signaling]
      })

    {[spec: spec], %{}}
  end
end
