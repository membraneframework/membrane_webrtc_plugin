defmodule PhoenixSignalingWeb.PageController do
  use PhoenixSignalingWeb, :controller

  alias Membrane.WebRTC.PhoenixSignaling

  def home(conn, _params) do
    unique_id = UUID.uuid4()

    Task.start(fn ->
      input_sg = PhoenixSignaling.new("#{unique_id}_egress")
      output_sg = PhoenixSignaling.new("#{unique_id}_ingress")

      Boombox.run(
        input: {:webrtc, input_sg},
        output: {:webrtc, output_sg}
      )
    end)

    render(conn, :home, layout: false, signaling_id: unique_id)
  end
end
