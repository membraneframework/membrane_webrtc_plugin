const pcConfig = { 'iceServers': [{ 'urls': 'stun:stun.l.google.com:19302' },] };
const mediaConstraints = { video: true, audio: true }

const proto = window.location.protocol === "https:" ? "wss:" : "ws:"
const ws = new WebSocket(`${proto}//${window.location.hostname}:8829`);
const conn_status = document.getElementById("status");
ws.onopen = _ => start_connection(ws);
ws.onclose = event => {
  conn_status.innerHTML = "Disconnected"
  console.log("WebSocket connection was terminated:", event);
}

const start_connection = async (ws) => {
  const pc = new RTCPeerConnection(pcConfig);

  pc.onicecandidate = event => {
    if (event.candidate === null) return;

    setTimeout(() => {
      console.log("Sent ICE candidate:", event.candidate);
      ws.send(JSON.stringify({ type: "ice_candidate", data: event.candidate }));
    }, 1000);
  };

  const localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
  for (const track of localStream.getTracks()) {
    pc.addTrack(track, localStream);
  }

  ws.onmessage = async event => {
    const { type, data } = JSON.parse(event.data);

    switch (type) {
      case "sdp_answer":
        console.log("Received SDP answer:", data);
        await pc.setRemoteDescription(data);
        const button = document.createElement('button');
        button.innerHTML = "Disconnect";
        button.onclick = () => ws.close();
        conn_status.innerHTML = "Connected ";
        conn_status.appendChild(button);
        break;
      case "ice_candidate":
        console.log("Recieved ICE candidate:", data);
        await pc.addIceCandidate(data);
        break;
    }
  };

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  console.log("Sent SDP offer:", offer)
  ws.send(JSON.stringify({ type: "sdp_offer", data: offer }));
};
