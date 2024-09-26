defmodule Membrane.WebRTC.Sink.VideoDispatcher do
  @moduledoc false
  use Membrane.Filter

  alias Membrane.{H264, RemoteStream, VP8}

  def_input_pad :input, accepted_format: any_of(H264, VP8, %RemoteStream{content_format: VP8})
  def_output_pad :h264_output, accepted_format: H264
  def_output_pad :vp8_output, accepted_format: any_of(VP8, %RemoteStream{content_format: VP8})

  @impl true
  def handle_init(ctx, _opts) do
    buffered_events = Map.keys(ctx.pads) |> Map.new(&{&1, []})
    {[], %{selected_output_pad: nil, buffered_events: buffered_events}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    selected_output_pad =
      case stream_format do
        %H264{} -> :h264_output
        %VP8{} -> :vp8_output
        %RemoteStream{content_format: VP8} -> :vp8_output
      end

    event_actions =
      state.buffered_events
      |> Enum.flat_map(fn
        {_pad, []} -> []
        {:input, events} -> [event: {selected_output_pad, Enum.reverse(events)}]
        {^selected_output_pad, events} -> [event: {:input, Enum.reverse(events)}]
        {_ignored_output_pad, _events} -> []
      end)

    state = %{state | selected_output_pad: selected_output_pad, buffered_events: %{}}
    actions = event_actions ++ [stream_format: {selected_output_pad, stream_format}]
    {actions, state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    {[buffer: {state.selected_output_pad, buffer}], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {[end_of_stream: :h264_output, end_of_stream: :vp8_output], state}
  end

  @impl true
  def handle_event(pad, event, _ctx, %{selected_output_pad: nil} = state) do
    state = update_in(state, [:buffered_events, pad], &[event | &1])
    {[], state}
  end

  @impl true
  def handle_event(pad, event, _ctx, %{selected_output_pad: selected_output_pad} = state) do
    case pad do
      :input -> {[event: {selected_output_pad, event}], state}
      ^selected_output_pad -> {[event: {:input, event}], state}
      _ignored_output_pad -> {[], state}
    end
  end
end
