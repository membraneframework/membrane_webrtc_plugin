defmodule Membrane.WebRTC.Utils do
  alias ExWebRTC.RTPCodecParameters

  def ice_servers, do: [%{urls: "stun:stun.l.google.com:19302"}]

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
      # sdp_fmtp_line: %ExSDP.Attribute.FMTP{
      #   pt: 96,
      #   level_asymmetry_allowed: true,
      #   packetization_mode: 1,
      #   profile_level_id: 0x42001F
      # }
    }

  def codec_params(:vp8),
    do: %RTPCodecParameters{
      payload_type: 102,
      mime_type: "video/VP8",
      clock_rate: 90_000
    }
end
