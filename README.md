# Membrane WebRTC Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_webrtc_plugin.svg)](https://hex.pm/packages/membrane_webrtc_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_webrtc_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_webrtc_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_webrtc_plugin)

Membrane Plugin for sending and receiving streams via WebRTC. It's based on [ex_webrtc](https://github.com/elixir-webrtc/ex_webrtc).

It's a part of the [Membrane Framework](https://membrane.stream).

## Installation

The package can be installed by adding `membrane_webrtc_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_webrtc_plugin, "~> 0.26.2"}
  ]
end
```

## Demos

The `examples` directory shows how to send and receive streams from a web browser.
There are the following three demos:
* `live_view` - a simple Phoenix LiveView project using `Membrane.WebRTC.Live.Player` and `Membrane.WebRTC.Live.Capture` to echo video stream
captured from the user's browser.
* `phoenix_signaling` - showcasing simple Phoenix application that uses `Membrane.WebRTC.PhoenixSignaling` to echo stream captured
from the user's browser and sent via WebRTC. See `assets/phoenix_signaling/README.md` for details on how to run the demo.
* `webrtc_signaling` - it consists of two scripts: `file_to_browser.exs` and `browser_to_file.exs`. The first one displays the stream from
the fixture file in the user's browser. The latter captures the user's camera input from the browser and saves it in the file.
To run one of these demos, type: `elixir <script_name>` and visit `http://localhost:4000`.

## Exchanging Signaling Messages

To establish a WebRTC connection you have to exchange WebRTC signaling messages between peers.
In `membrane_webrtc_plugin` it can be done by the user, with `Membrane.WebRTC.Signaling` or by passing WebSocket address to
`Membrane.WebRTC.Source` or `Membrane.WebRTC.Sink`, but there are two additional ways of doing it, dedicated to be used within
`Phoenix` projects:
 - The first one is to use `Membrane.WebRTC.PhoenixSignaling` along with `Membrane.WebRTC.PhoenixSignaling.Socket`
 - The second one is to use `Phoenix.LiveView` `Membrane.WebRTC.Live.Player` or `Membrane.WebRTC.Live.Capture`. These modules expect
 `t:Membrane.WebRTC.Signaling.t/0` as an argument and take advantage of WebSocket used by `Phoenix.LiveView` to exchange WebRTC
 signaling messages, so there is no need to add any code to handle signaling messages.

### How to use Membrane.WebRTC.PhoenixSignaling in your own Phoenix project?

The see the full example, visit `example/phoenix_signaling`.

1. Create a new socket in your application endpoint, using the `Membrane.WebRTC.PhoenixSignaling.Socket`, for instance at `/signaling` path:
```
socket "/signaling", Membrane.WebRTC.PhoenixSignaling.Socket,
  websocket: true,
  longpoll: false
```
2. Create a Phoenix signaling channel with the desired signaling ID and use it as `Membrane.WebRTC.Signaling.t()`
for `Membrane.WebRTC.Source`, `Membrane.WebRTC.Sink` or [`Boombox`](https://github.com/membraneframework/boombox):
```
signaling = Membrane.WebRTC.PhoenixSignaling.new("<signaling_id>")

# use it with Membrane.WebRTC.Source:
child(:webrtc_source, %Membrane.WebRTC.Source{signaling: signaling})
|> ...

# or with Membrane.WebRTC.Sink:
...
|> child(:webrtc_sink, %Membrane.WebRTC.Sink{signaling: signaling})

# or with Boombox:
Boombox.run(
  input: {:webrtc, signaling},
  output: ...
)
```

>Please note that `signaling_id` is expected to be globally unique for each WebRTC connection about to be
>estabilished. You can, for instance:
>1. Generate a unique id with `:uuid` package and assign it to the connection in the page controller:
>```
>unique_id = UUID.uuid4()
>render(conn, :home, layout: false, signaling_id: unique_id)
>```
>
>2. Generate HTML based on HEEx template, using the previously set assign:
>```
><video id="videoPlayer" controls muted autoplay signaling_id={@signaling_id}></video>
>```
>
>3. Access it in your client code:
>```
>const videoPlayer = document.getElementById('videoPlayer');
>const signalingId = videoPlayer.getAttribute('signaling_id');
>```


3. Use the Phoenix Socket to exchange WebRTC signaling data.
```
let socket = new Socket("/signaling", {params: {token: window.userToken}})
socket.connect()
let channel = socket.channel('<signaling_id>')
channel.join()
  .receive("ok", resp => { console.log("Signaling socket joined successfully", resp)
    // here you can exchange WebRTC data
  })
  .receive("error", resp => { console.log("Unable to join signaling socket", resp) })
```

Visit `examples/phoenix_signaling/assets/js/signaling.js` to see how WebRTC signaling messages exchange might look like.

## Integrating Phoenix.LiveView with Membrane WebRTC Plugin

`membrane_webrtc_plugin` comes with two `Phoenix.LiveView`s:
 - `Membrane.WebRTC.Live.Capture` - exchanges WebRTC signaling messages between `Membrane.WebRTC.Source` and the browser. It
 expects the same `Membrane.WebRTC.Signaling` that has been passed to the related `Membrane.WebRTC.Source`. As a result,
 `Membrane.Webrtc.Source` will return the media stream captured from the browser, where `Membrane.WebRTC.Live.Capture` has been
 rendered.
 - `Membrane.WebRTC.Live.Player` - exchanges WebRTC signaling messages between `Membrane.WebRTC.Sink` and the browser. It
 expects the same `Membrane.WebRTC.Signaling` that has been passed to the related `Membrane.WebRTC.Sink`. As a result,
 `Membrane.WebRTC.Live.Player` will play media streams passed to the related `Membrane.WebRTC.Sink`. Currently supports up
 to one video stream and up to one audio stream.

### Usage

To use `Phoenix.LiveView`s from this repository, you have to use related JS hooks. To do so, add the following code snippet to `assets/js/app.js`

```js
import { createCaptureHook, createPlayerHook } from "membrane_webrtc_plugin";

let Hooks = {};
const iceServers = [{ urls: "stun:stun.l.google.com:19302" }];
Hooks.Capture = createCaptureHook(iceServers);
Hooks.Player = createPlayerHook(iceServers);
```

and add `Hooks` to the WebSocket constructor. It can be done in the following way:

```js
new LiveSocket("/live", Socket, {
  params: SomeParams,
  hooks: Hooks,
});
```

To see the full usage example, you can go to `examples/live_view/` directory in this repository (take a look especially at `examples/live_view/assets/js/app.js` and `examples/live_view/lib/example_project_web/live_views/echo.ex`).

## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_webrtc_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_webrtc_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
