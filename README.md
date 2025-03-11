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
    {:membrane_webrtc_plugin, "~> 0.25.0"}
  ]
end
```

## Usage

The `examples` directory shows how to send and receive streams from a web browser.
There are following two demos there:
* `phoenix_signaling` - showcasing simple Phoenix application that uses `Membrane.WebRTC.PhoenixSignaling` to echo stream captured
from the user's browser and sent via WebRTC. See `assets/phoenix_signaling/README.md` for details on how to run the demo.
* `webrtc_signaling` - it consists of two scripts: `file_to_browser.exs` and `browser_to_file.exs`. The first one display stream from
the fixture file in the user's browser. The later one captures user's camera input from the browser and saves it in the file.
To run one of these demos, type: `elixir <script_name>` and visit `http://localhost:4000`.

## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_webrtc_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_webrtc_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
