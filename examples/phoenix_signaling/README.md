# PhoenixSignaling

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
You should be able to see a video player displaying video captured from your camera.

## How to use PhoenixSignaling in your own Phoenix project?

1. Create new socket in your application endpoint, using the `Membrane.WebRTC.PhoenixSignaling.Socket`, for instance at `/signaling` path:
```
  socket "/signaling", Membrane.WebRTC.PhoenixSignaling.Socket,
  websocket: true,
  longpoll: false
```
2. Create a Phoenix signaling channel with desired signaling ID, for instance in your controller:
```
signaling = Membrane.WebRTC.PhoenixSignaling.new("<signaling_id>")
```

>Please note that `signaling_id` is expected to be unique for each WebRTC connection about to be
>estabilished. You can, for instance:
>1. Generate unique id with `:uuid` package and assign to the connection in the page controller:
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
let socket = new Socket("/singaling", {params: {token: window.userToken}})
socket.connect()
let channel = socket.channel('<signaling_id>')
channel.join()
  .receive("ok", resp => { console.log("Joined successfully", resp)
    // here you can exchange WebRTC data
  })
  .receive("error", resp => { console.log("Unable to join", resp) })
```

Visit `assets/js/app.js` to see how WebRTC exchange can be done.
