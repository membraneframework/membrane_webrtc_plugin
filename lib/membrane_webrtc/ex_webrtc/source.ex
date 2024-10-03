defmodule Membrane.WebRTC.ExWebRTCSource do
  @moduledoc false

  use Membrane.Source

  require Membrane.Logger

  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}
  alias Membrane.WebRTC.{ExWebRTCUtils, SignalingChannel, SimpleWebSocketServer}

  def_options signaling: [], video_codec: [], ice_servers: [], keyframe_interval: []

  def_output_pad :output,
    accepted_format: Membrane.RTP,
    availability: :on_request,
    flow_control: :push,
    options: [kind: [default: nil]]

  defmodule State do
    @moduledoc false

    @type output_track :: %{
            status: :awaiting | :connected,
            pad: Membrane.Pad.ref() | nil,
            track: ExWebRTC.MediaStreamTrack.t(),
            first_packet_received: boolean()
          }

    @type t :: %__MODULE__{
            pc: pid() | nil,
            output_tracks: %{(pad_id :: term()) => output_track()},
            awaiting_outputs: [{:video | :audio, Membrane.Pad.ref()}],
            awaiting_candidates: [ExWebRTC.ICECandidate.t()],
            signaling: SignalingChannel.t() | {:websocket, SimpleWebSocketServer.options()},
            status: :init | :connecting | :connected | :closed,
            audio_params: [ExWebRTC.RTPCodecParameters.t()],
            video_params: [ExWebRTC.RTPCodecParameters.t()],
            video_codecs: [:h264 | :vp8],
            ice_servers: [ExWebRTC.PeerConnection.Configuration.ice_server()],
            keyframe_interval: Membrane.Time.t() | nil
          }

    @enforce_keys [
      :signaling,
      :audio_params,
      :video_codecs,
      :ice_servers,
      :keyframe_interval
    ]
    defstruct @enforce_keys ++
                [
                  video_params: nil,
                  pc: nil,
                  output_tracks: %{},
                  awaiting_outputs: [],
                  awaiting_candidates: [],
                  status: :init
                ]
  end

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %State{
       signaling: opts.signaling,
       audio_params: ExWebRTCUtils.codec_params(:opus),
       video_codecs: Bunch.listify(opts.video_codec),
       ice_servers: opts.ice_servers,
       keyframe_interval: opts.keyframe_interval
     }}
  end

  @impl true
  def handle_setup(ctx, state) do
    signaling =
      with {:websocket, opts} <- state.signaling do
        SimpleWebSocketServer.start_link_supervised(ctx.utility_supervisor, opts)
      end

    {[], %{state | signaling: signaling}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    Process.monitor(state.signaling.pid)
    SignalingChannel.register_element(state.signaling)

    {[], %{state | status: :connecting}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, _id) = pad, %{playback: :stopped} = ctx, state) do
    %{kind: kind} = ctx.pad_options
    state = %{state | awaiting_outputs: state.awaiting_outputs ++ [{kind, pad}]}
    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, pad_id) = pad, _ctx, state) do
    state =
      state
      |> Bunch.Struct.update_in([:output_tracks, pad_id], fn output_track ->
        %{output_track | status: :connected, pad: pad}
      end)
      |> maybe_answer()

    {[stream_format: {pad, %Membrane.RTP{}}], state}
  end

  @impl true
  def handle_event(pad, %Membrane.KeyframeRequestEvent{}, _ctx, state) do
    track_id =
      state.output_tracks
      |> Enum.find_value(fn
        {track_id, %{status: :connected, pad: ^pad}} -> track_id
        _other -> false
      end)

    if track_id do
      Membrane.Logger.debug("Sending PLI on track #{inspect(track_id)}")
      :ok = PeerConnection.send_pli(state.pc, track_id)
    end

    {[], state}
  end

  @impl true
  def handle_event(pad, event, _ctx, state) do
    Membrane.Logger.debug("Ignoring event #{inspect(event)} that arrived on pad #{inspect(pad)}")
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, _msg}, _ctx, %{status: :closed} = state) do
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:rtp, id, _rid, packet}}, _ctx, state) do
    buffer = %Membrane.Buffer{
      payload: packet.payload,
      metadata: %{rtp: packet |> Map.from_struct() |> Map.delete(:payload)}
    }

    case state.output_tracks[id] do
      %{status: :awaiting, track: track} ->
        Membrane.Logger.warning("""
        Dropping packet of track #{inspect(id)}, kind #{inspect(track.kind)} \
        that arrived before the SDP answer was sent.
        """)

        {[], state}

      %{status: :connected, pad: pad, track: %{kind: kind}, first_packet_received: false} ->
        timer_action =
          if kind == :video and state.keyframe_interval != nil do
            [start_timer: {{:request_keyframe, id}, state.keyframe_interval}]
          else
            []
          end

        state =
          Bunch.Struct.update_in(state, [:output_tracks, id], fn output_track ->
            %{output_track | first_packet_received: true}
          end)

        {[buffer: {pad, buffer}] ++ timer_action, state}

      %{status: :connected, pad: pad} ->
        {[buffer: {pad, buffer}], state}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:ice_candidate, candidate}}, _ctx, state) do
    SignalingChannel.signal(state.signaling, candidate)
    {[], state}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, {:connection_state_change, :connected}}, _ctx, state) do
    {[], %{state | status: :connected}}
  end

  @impl true
  def handle_info({:ex_webrtc, _from, message}, _ctx, state) do
    Membrane.Logger.debug("Ignoring ex_webrtc message: #{inspect(message)}")
    {[], state}
  end

  @impl true
  def handle_info({SignalingChannel, _pid, %SessionDescription{type: :offer} = sdp}, _ctx, state) do
    Membrane.Logger.debug("Received SDP offer")

    state =
      with %{pc: nil} <- state do
        state =
          ExWebRTCUtils.get_video_codecs_from_sdp(sdp)
          |> select_video_params(state)

        {:ok, pc} =
          PeerConnection.start(
            ice_servers: state.ice_servers,
            video_codecs: state.video_params,
            audio_codecs: state.audio_params
          )

        Process.monitor(pc)

        %{state | pc: pc}
      end

    :ok = PeerConnection.set_remote_description(state.pc, sdp)

    {new_tracks, awaiting_outputs} =
      receive_new_tracks()
      |> Enum.map_reduce(state.awaiting_outputs, fn track, awaiting_outputs ->
        case List.keytake(awaiting_outputs, track.kind, 0) do
          nil ->
            {{track.id,
              %{status: :awaiting, track: track, pad: nil, first_packet_received: false}},
             awaiting_outputs}

          {{_kind, pad}, awaiting_outputs} ->
            {{track.id,
              %{status: :connected, track: track, pad: pad, first_packet_received: false}},
             awaiting_outputs}
        end
      end)

    output_tracks = Map.merge(state.output_tracks, Map.new(new_tracks))

    state =
      %{state | awaiting_outputs: awaiting_outputs, output_tracks: output_tracks}
      |> maybe_answer()

    tracks_notification =
      Enum.flat_map(new_tracks, fn
        {_id, %{status: :awaiting, track: track}} -> [track]
        _connected_track -> []
      end)
      |> case do
        [] -> []
        tracks -> [notify_parent: {:new_tracks, tracks}]
      end

    stream_formats =
      Enum.flat_map(new_tracks, fn
        {_id, %{status: :connected, pad: pad}} ->
          [stream_format: {pad, %Membrane.RTP{}}]

        _other ->
          []
      end)

    {tracks_notification ++ stream_formats, state}
  end

  @impl true
  def handle_info({SignalingChannel, _pid, %ICECandidate{} = candidate}, _ctx, state) do
    case PeerConnection.add_ice_candidate(state.pc, candidate) do
      :ok ->
        {[], state}

      # Workaround for a bug in ex_webrtc that should be fixed in 0.2.0
      {:error, :no_remote_description} ->
        {[], %{state | awaiting_candidates: [candidate | state.awaiting_candidates]}}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, _monitor, :process, signaling_pid, _reason},
        ctx,
        %{signaling: %{pid: signaling_pid}} = state
      ) do
    handle_close(ctx, state)
  end

  @impl true
  def handle_info(
        {:DOWN, _monitor, :process, pc, _reason},
        ctx,
        %{pc: pc} = state
      ) do
    handle_close(ctx, state)
  end

  @impl true
  def handle_tick({:request_keyframe, track_id}, _ctx, state) do
    :ok = PeerConnection.send_pli(state.pc, track_id)
    {[], state}
  end

  defp maybe_answer(state) do
    if Enum.all?(state.output_tracks, fn {_id, %{status: status}} -> status == :connected end) do
      %{pc: pc} = state
      {:ok, answer} = PeerConnection.create_answer(pc)
      :ok = PeerConnection.set_local_description(pc, answer)

      state.awaiting_candidates
      |> Enum.reverse()
      |> Enum.each(&(:ok = PeerConnection.add_ice_candidate(pc, &1)))

      SignalingChannel.signal(state.signaling, answer)
      %{state | awaiting_candidates: []}
    else
      state
    end
  end

  @spec receive_new_tracks() :: [ExWebRTC.MediaStreamTrack.t()]
  defp receive_new_tracks(), do: do_receive_new_tracks([])

  defp do_receive_new_tracks(acc) do
    receive do
      {:ex_webrtc, _pc, {:track, track}} -> do_receive_new_tracks([track | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp handle_close(_ctx, %{status: :connecting}) do
    raise "Connection failed"
  end

  defp handle_close(%{playback: :playing} = ctx, %{status: status} = state)
       when status != :closed do
    actions =
      ctx.pads
      |> Map.values()
      |> Enum.filter(&(&1.direction == :output))
      |> Enum.map(&{:end_of_stream, &1.ref})

    {actions, %{state | status: :closed}}
  end

  defp handle_close(_ctx, state) do
    {[], %{state | status: :closed}}
  end

  defp select_video_params(video_codecs_in_sdp_offer, state) do
    selected_codec =
      case state.video_codecs do
        [] ->
          []

        [only_codec] ->
          only_codec

        [preferred_codec, second_codec] ->
          if preferred_codec in video_codecs_in_sdp_offer,
            do: preferred_codec,
            else: second_codec
      end

    video_params = ExWebRTCUtils.codec_params(selected_codec)
    %{state | video_params: video_params}
  end
end
