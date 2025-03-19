# Example Project

Example project showing how `Membrane.WebRTC.Live.Capture` and `Membrane.WebRTC.Live.Player` can be used.

It contains a simple demo, where:
 - the video stream is get from the browser and sent via WebRTC to Elixir server using `Membrane.WebRTC.Live.Capture`
 - then, this same video stream is re-sent again to the browser and displayed using `Membrane.WebRTC.Live.Player`.

This demo uses also [Boombox](https://hex.pm/packages/boombox).

The most important file in the project is `example_project/lib/example_project_web/live_views/echo.ex`, that 
contains the usage of `Boombox` and  LiveViews defined in `membrane_webrtc_plugin` package.

You can also take a look at `example_project/assets/js/app.js` to see how you can use JS hooks from `membrane_webrtc_plugin`.

## Run server

To start Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
