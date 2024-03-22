defmodule Membrane.WebRTC.Utils do
  @moduledoc false

  alias ExWebRTC.RTPCodecParameters

  @spec codec_params(:opus | :h264 | :vp8) :: RTPCodecParameters.t()
  def codec_params(:opus),
    do: %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }

  def codec_params(:h264),
    do: %RTPCodecParameters{
      payload_type: 96,
      mime_type: "video/H264",
      clock_rate: 90_000
    }

  def codec_params(:vp8),
    do: %RTPCodecParameters{
      payload_type: 102,
      mime_type: "video/VP8",
      clock_rate: 90_000
    }
end
