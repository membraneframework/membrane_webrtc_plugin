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
    pt = 96
    rtx_pt = 97

    [
      %RTPCodecParameters{
        payload_type: pt,
        mime_type: "video/H264",
        clock_rate: codec_clock_rate(:h264),
        rtcp_fbs: [%ExSDP.Attribute.RTCPFeedback{pt: pt, feedback_type: :nack}]
      },
      %RTPCodecParameters{
        payload_type: rtx_pt,
        mime_type: "video/rtx",
        clock_rate: codec_clock_rate(:h264),
        sdp_fmtp_line: %ExSDP.Attribute.FMTP{pt: rtx_pt, apt: pt}
      }
    ]
  end

  def codec_params(:vp8) do
    pt = 102
    rtx_pt = 103

    [
      %RTPCodecParameters{
        payload_type: pt,
        mime_type: "video/VP8",
        clock_rate: codec_clock_rate(:vp8),
        rtcp_fbs: [%ExSDP.Attribute.RTCPFeedback{pt: pt, feedback_type: :nack}]
      },
      %RTPCodecParameters{
        payload_type: rtx_pt,
        mime_type: "video/rtx",
        clock_rate: codec_clock_rate(:vp8),
        sdp_fmtp_line: %ExSDP.Attribute.FMTP{pt: rtx_pt, apt: pt}
      }
    ]
  end

  @spec codec_clock_rate(:opus | :h264 | :vp8) :: pos_integer()
  def codec_clock_rate(:opus), do: 48_000
  def codec_clock_rate(:vp8), do: 90_000
  def codec_clock_rate(:h264), do: 90_000
end
