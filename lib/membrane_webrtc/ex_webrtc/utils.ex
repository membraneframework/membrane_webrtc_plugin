defmodule Membrane.WebRTC.ExWebRTCUtils do
  @moduledoc false

  alias ExWebRTC.RTPCodecParameters

  @type codec :: :opus | :h264 | :vp8 | :av1
  @type codec_or_codecs :: codec() | [codec()]

  @spec codec_params(codec_or_codecs()) :: [RTPCodecParameters.t()]
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
        clock_rate: codec_clock_rate(:h264),
        sdp_fmtp_line: %ExSDP.Attribute.FMTP{
          pt: 96,
          level_asymmetry_allowed: true,
          packetization_mode: 1,
          profile_level_id: 0x42E01F
        }
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

  def codec_params(:av1) do
    [
      %RTPCodecParameters{
        payload_type: 45,
        mime_type: "video/AV1",
        clock_rate: codec_clock_rate(:av1),
        sdp_fmtp_line: %ExSDP.Attribute.FMTP{
          pt: 45,
          profile: 0,
          level_idx: 5,
          tier: 0
        }
      }
    ]
  end

  def codec_params(codecs) when is_list(codecs) do
    codecs |> Enum.flat_map(&codec_params/1)
  end

  @spec codec_clock_rate(codec_or_codecs()) :: pos_integer()
  def codec_clock_rate(:opus), do: 48_000
  def codec_clock_rate(:vp8), do: 90_000
  def codec_clock_rate(:h264), do: 90_000
  def codec_clock_rate(:av1), do: 90_000

  def codec_clock_rate(codecs) when is_list(codecs) do
    cond do
      codecs == [:opus] ->
        48_000

      codecs != [] and Enum.all?(codecs, &(&1 in [:vp8, :h264])) ->
        90_000
    end
  end

  @spec get_video_codecs_from_sdp(ExWebRTC.SessionDescription.t()) :: [:h264 | :vp8 | :av1]
  def get_video_codecs_from_sdp(%ExWebRTC.SessionDescription{sdp: sdp}) do
    ex_sdp = ExSDP.parse!(sdp)

    ex_sdp.media
    |> Enum.flat_map(fn
      %{type: :video, attributes: attributes} -> attributes
      _media -> []
    end)
    |> Enum.flat_map(fn
      %ExSDP.Attribute.RTPMapping{encoding: "H264"} -> [:h264]
      %ExSDP.Attribute.RTPMapping{encoding: "VP8"} -> [:vp8]
      %ExSDP.Attribute.RTPMapping{encoding: "AV1"} -> [:av1]
      _attribute -> []
    end)
    |> Enum.uniq()
  end
end
