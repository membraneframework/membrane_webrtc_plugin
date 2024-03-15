defmodule Membrane.WebRTC.IntegrationTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  require Membrane.Pad, as: Pad

  alias Membrane.Testing
  alias Membrane.WebRTC
  alias Membrane.WebRTC.SignalingChannel

  @tag :tmp_dir
  test "send and receive a file", %{tmp_dir: tmp_dir} do
    test_process = self()

    signaling_forwarder =
      ExUnit.Callbacks.start_link_supervised!({
        Task,
        fn ->
          send_signaling = SignalingChannel.new()
          receive_signaling = SignalingChannel.new()
          send(test_process, {send_signaling, receive_signaling})
          forward_signaling_messages(send_signaling, receive_signaling)
        end
      })

    assert_receive {send_signaling, receive_signaling}

    send_pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec:
          child(%Membrane.File.Source{location: "test/fixtures/input_bbb.mkv"})
          |> child(:demuxer, Membrane.Matroska.Demuxer)
      )

    assert_pipeline_notified(send_pipeline, :demuxer, {:new_track, {video_id, %{codec: :vp8}}})
    assert_pipeline_notified(send_pipeline, :demuxer, {:new_track, {audio_id, %{codec: :opus}}})

    Testing.Pipeline.execute_actions(send_pipeline,
      spec: [
        child(:webrtc, %WebRTC.Sink{signaling: send_signaling}),
        get_child(:demuxer)
        |> via_out(Pad.ref(:output, video_id))
        |> child(Membrane.Realtimer)
        |> via_in(Pad.ref(:input, :video), options: [kind: :video])
        |> get_child(:webrtc),
        get_child(:demuxer)
        |> via_out(Pad.ref(:output, audio_id))
        |> child(Membrane.Realtimer)
        |> via_in(Pad.ref(:input, :audio), options: [kind: :audio])
        |> get_child(:webrtc)
      ]
    )

    receive_pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec: [
          child(:webrtc, %WebRTC.Source{signaling: receive_signaling}),
          get_child(:webrtc)
          |> via_out(:output, options: [kind: :audio])
          |> child(Membrane.Opus.Parser)
          |> child(:audio_sink, %Membrane.File.Sink{location: "#{tmp_dir}/out_audio"}),
          get_child(:webrtc)
          |> via_out(:output, options: [kind: :video])
          |> child(:video_sink, %Membrane.File.Sink{location: "#{tmp_dir}/out_video"})
        ]
      )

    assert_pipeline_notified(send_pipeline, :webrtc, {:end_of_stream, :audio}, 30_000)
    assert_pipeline_notified(send_pipeline, :webrtc, {:end_of_stream, :video}, 1_000)
    # Time for the stream to arrive to the receiver
    Process.sleep(200)
    Testing.Pipeline.terminate(send_pipeline)
    send(signaling_forwarder, :exit)
    assert_end_of_stream(receive_pipeline, :audio_sink, :input, 1_000)
    assert_end_of_stream(receive_pipeline, :video_sink, :input, 1_000)
    Testing.Pipeline.terminate(receive_pipeline)
    assert File.read!("#{tmp_dir}/out_audio") == File.read!("test/fixtures/ref_audio")
    assert File.read!("#{tmp_dir}/out_video") == File.read!("test/fixtures/ref_video")
  end

  defp forward_signaling_messages(%{pid: pid_a} = signaling_a, %{pid: pid_b} = signaling_b) do
    receive do
      :exit ->
        :ok

      message ->
        case message do
          {SignalingChannel, ^pid_a, msg} -> SignalingChannel.signal(signaling_b, msg)
          {SignalingChannel, ^pid_b, msg} -> SignalingChannel.signal(signaling_a, msg)
        end

        forward_signaling_messages(signaling_a, signaling_b)
    end
  end
end
