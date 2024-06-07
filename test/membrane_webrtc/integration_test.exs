defmodule Membrane.WebRTC.IntegrationTest do
  # Tests are split into submodules so that they run concurrently
  # credo:disable-for-this-file Credo.Check.Readability.Specs

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  require Membrane.Pad, as: Pad

  alias Membrane.Testing
  alias Membrane.WebRTC
  alias Membrane.WebRTC.SignalingChannel

  defmodule Utils do
    import ExUnit.Assertions

    def fixture_processing_timeout, do: 30_000

    def prepare_input(pipeline, opts) do
      demuxer_name = {:demuxer, make_ref()}

      Testing.Pipeline.execute_actions(pipeline,
        spec:
          child(%Membrane.File.Source{location: "test/fixtures/input_bbb.mkv"})
          |> child(demuxer_name, Membrane.Matroska.Demuxer)
      )

      assert_pipeline_notified(
        pipeline,
        demuxer_name,
        {:new_track, {mkv_video_id, %{codec: :vp8}}}
      )

      assert_pipeline_notified(
        pipeline,
        demuxer_name,
        {:new_track, {mkv_audio_id, %{codec: :opus}}}
      )

      webrtc = if opts[:webrtc], do: [child(:webrtc, opts[:webrtc])], else: []

      Testing.Pipeline.execute_actions(pipeline,
        spec: [
          webrtc,
          get_child(demuxer_name)
          |> via_out(Pad.ref(:output, mkv_audio_id))
          |> child(Membrane.Realtimer)
          |> via_in(Pad.ref(:input, opts[:webrtc_audio_id] || :audio), options: [kind: :audio])
          |> get_child(:webrtc),
          get_child(demuxer_name)
          |> via_out(Pad.ref(:output, mkv_video_id))
          |> child(Membrane.Realtimer)
          |> via_in(Pad.ref(:input, opts[:webrtc_video_id] || :video), options: [kind: :video])
          |> get_child(:webrtc)
        ]
      )
    end

    def prepare_output(pipeline, tmp_dir, opts) do
      webrtc = if opts[:webrtc], do: [child(:webrtc, opts[:webrtc])], else: []
      id = opts[:output_id] || ""

      Testing.Pipeline.execute_actions(pipeline,
        spec: [
          webrtc,
          get_child(:webrtc)
          |> via_out(Pad.ref(:output, opts[:webrtc_audio_id] || :audio), options: [kind: :audio])
          |> child(Membrane.Opus.Parser)
          |> child({:audio_sink, id}, %Membrane.File.Sink{location: "#{tmp_dir}/out_audio#{id}"}),
          get_child(:webrtc)
          |> via_out(Pad.ref(:output, opts[:webrtc_video_id] || :video), options: [kind: :video])
          |> child({:video_sink, id}, %Membrane.File.Sink{location: "#{tmp_dir}/out_video#{id}"})
        ]
      )
    end
  end

  defmodule SendRecv do
    use ExUnit.Case, async: true

    import Utils

    @tag :tmp_dir
    test "send and receive a file", %{tmp_dir: tmp_dir} do
      signaling = SignalingChannel.new()
      send_pipeline = Testing.Pipeline.start_link_supervised!()
      prepare_input(send_pipeline, webrtc: %WebRTC.Sink{signaling: signaling})
      receive_pipeline = Testing.Pipeline.start_link_supervised!()

      prepare_output(receive_pipeline, tmp_dir, webrtc: %WebRTC.Source{signaling: signaling})

      assert_pipeline_notified(
        send_pipeline,
        :webrtc,
        {:end_of_stream, :audio},
        fixture_processing_timeout()
      )

      assert_pipeline_notified(send_pipeline, :webrtc, {:end_of_stream, :video}, 1_000)
      # Time for the stream to arrive to the receiver
      Process.sleep(200)
      Testing.Pipeline.terminate(send_pipeline)
      assert_end_of_stream(receive_pipeline, {:audio_sink, _id}, :input, 1_000)
      assert_end_of_stream(receive_pipeline, {:video_sink, _id}, :input, 1_000)
      Testing.Pipeline.terminate(receive_pipeline)
      assert File.read!("#{tmp_dir}/out_audio") == File.read!("test/fixtures/ref_audio")
      assert File.read!("#{tmp_dir}/out_video") == File.read!("test/fixtures/ref_video")
    end
  end

  defmodule DynamicTracks do
    use ExUnit.Case, async: false

    import Utils

    @tag :tmp_dir
    test "dynamically add new tracks", %{tmp_dir: tmp_dir} do
      signaling = SignalingChannel.new()

      send_pipeline = Testing.Pipeline.start_link_supervised!()
      prepare_input(send_pipeline, webrtc: %WebRTC.Sink{signaling: signaling})

      receive_pipeline = Testing.Pipeline.start_link_supervised!()

      prepare_output(receive_pipeline, tmp_dir,
        output_id: 1,
        webrtc: %WebRTC.Source{signaling: signaling}
      )

      assert_start_of_stream(receive_pipeline, {:audio_sink, 1}, :input)
      assert_start_of_stream(receive_pipeline, {:video_sink, 1}, :input)

      Process.sleep(1500)

      Testing.Pipeline.message_child(send_pipeline, :webrtc, {:add_tracks, [:audio, :video]})

      assert_pipeline_notified(receive_pipeline, :webrtc, {:new_tracks, tracks})

      assert [%{kind: :audio, id: audio_id}, %{kind: :video, id: video_id}] =
               Enum.sort_by(tracks, & &1.kind)

      prepare_output(receive_pipeline, tmp_dir,
        output_id: 2,
        webrtc_audio_id: audio_id,
        webrtc_video_id: video_id
      )

      assert_pipeline_notified(send_pipeline, :webrtc, {:new_tracks, tracks})

      assert [%{kind: :audio, id: audio_id}, %{kind: :video, id: video_id}] =
               Enum.sort_by(tracks, & &1.kind)

      prepare_input(send_pipeline, webrtc_audio_id: audio_id, webrtc_video_id: video_id)

      assert_pipeline_notified(
        send_pipeline,
        :webrtc,
        {:end_of_stream, :audio},
        fixture_processing_timeout()
      )

      assert_pipeline_notified(send_pipeline, :webrtc, {:end_of_stream, :video}, 1_000)
      assert_pipeline_notified(send_pipeline, :webrtc, {:end_of_stream, ^audio_id}, 3_000)
      assert_pipeline_notified(send_pipeline, :webrtc, {:end_of_stream, ^video_id}, 1_000)
      # Time for the stream to arrive to the receiver
      Process.sleep(200)
      Testing.Pipeline.terminate(send_pipeline)

      Enum.each([audio_sink: 1, video_sink: 1, audio_sink: 2, video_sink: 2], fn element ->
        assert_end_of_stream(receive_pipeline, ^element, :input, 1_000)
      end)

      Testing.Pipeline.terminate(receive_pipeline)
      assert File.read!("#{tmp_dir}/out_audio1") == File.read!("test/fixtures/ref_audio")
      assert File.read!("#{tmp_dir}/out_video1") == File.read!("test/fixtures/ref_video")
      assert File.read!("#{tmp_dir}/out_audio2") == File.read!("test/fixtures/ref_audio")
      assert File.read!("#{tmp_dir}/out_video2") == File.read!("test/fixtures/ref_video")
    end
  end
end
