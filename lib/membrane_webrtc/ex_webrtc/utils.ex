defmodule Membrane.WebRTC.ExWebRTCUtils do
  @moduledoc false

  alias ExWebRTC.RTPCodecParameters

  @spec codec_params(:opus | :h264 | :vp8) :: [RTPCodecParameters.t()]
  def codec_params(:opus),
    do: [
      %RTPCodecParameters{
        payload_type: 111,
        mime_type: "audio/opus",
        clock_rate: codec_clock_rate(:opus),
        channels: 2
      }
    ]

  def codec_params(:h264) do
    [
      %RTPCodecParameters{
        payload_type: 96,
        mime_type: "video/H264",
        clock_rate: codec_clock_rate(:h264)
      }
    ]
  end

  def codec_params(:vp8) do
    [
      %RTPCodecParameters{
        payload_type: 102,
        mime_type: "video/VP8",
        clock_rate: codec_clock_rate(:vp8)
      }
    ]
  end

  def parse_ip_to_tuple(ip) do
    String.split(ip, ".")
    |> Enum.map(fn x ->
      {number, _rest} = Integer.parse(x)
      number
    end)
    |> List.to_tuple()
  end

  @spec codec_clock_rate(:opus | :h264 | :vp8) :: pos_integer()
  def codec_clock_rate(:opus), do: 48_000
  def codec_clock_rate(:vp8), do: 90_000
  def codec_clock_rate(:h264), do: 90_000
end
