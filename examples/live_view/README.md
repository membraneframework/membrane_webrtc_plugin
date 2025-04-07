# Example Project

Example project showing how `Membrane.WebRTC.Live.Capture` and `Membrane.WebRTC.Live.Player` can be used.

It contains a simple demo, where:
 - the video stream is get from the browser and sent via WebRTC to Elixir server using `Membrane.WebRTC.Live.Capture`
 - then, this same video stream is re-sent again to the browser and displayed using `Membrane.WebRTC.Live.Player`.

Usage of Phoenix LiveViews dedicated for Membrane WebRTC takes place in `lib/webrtc_live_view_web/live/home.ex`.

## Running the demo

To run the demo, you'll need to have [Elixir installed](https://elixir-lang.org/install.html). Then, do the following:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
