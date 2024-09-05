defmodule Membrane.WebRTC.KeyframeRequester do
  @moduledoc false
  use Membrane.Filter

  alias Membrane.{Buffer, KeyframeRequestEvent}

  def_options keyframe_interval: [
                spec: Membrane.Time.t()
              ]

  def_input_pad :input, accepted_format: _any, flow_control: :auto

  def_output_pad :output, accepted_format: _any, flow_control: :auto

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{keyframe_interval: opts.keyframe_interval, last_keyframe_request_ts: 0}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{keyframe_interval: nil} = state) do
    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{pts: pts} = buffer, _ctx, state) do
    keyframe_request_action =
      if pts - state.last_keyframe_request_ts >= state.keyframe_interval do
        [event: {:input, %KeyframeRequestEvent{}}]
      else
        []
      end

    {keyframe_request_action ++ [buffer: {:output, buffer}], state}
  end
end
