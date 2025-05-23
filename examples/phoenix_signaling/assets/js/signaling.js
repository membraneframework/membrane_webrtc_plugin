import { Socket } from "phoenix";

async function startEgressConnection(channel, topic) {
  const pcConfig = { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };
  const mediaConstraints = { video: true, audio: true };

  const connStatus = document.getElementById("status");
  const localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
  const pc = new RTCPeerConnection(pcConfig);

  pc.onicecandidate = (event) => {
    if (event.candidate === null) return;
    console.log("Sent ICE candidate:", event.candidate);
    channel.push(topic, JSON.stringify({ type: "ice_candidate", data: event.candidate }));
  };

  pc.onconnectionstatechange = () => {
    if (pc.connectionState == "connected") {
      const button = document.createElement("button");
      button.innerHTML = "Disconnect";
      button.onclick = () => {
        localStream.getTracks().forEach((track) => track.stop());
      };
      connStatus.innerHTML = "Connected ";
      connStatus.appendChild(button);
    }
  };

  for (const track of localStream.getTracks()) {
    pc.addTrack(track, localStream);
  }

  channel.on(topic, async (payload) => {
    type = payload.type;
    data = payload.data;

    switch (type) {
      case "sdp_answer":
        console.log("Received SDP answer:", data);
        await pc.setRemoteDescription(data);
        break;
      case "ice_candidate":
        console.log("Received ICE candidate:", data);
        await pc.addIceCandidate(data);
        break;
    }
  });

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  console.log("Sent SDP offer:", offer);
  channel.push(topic, JSON.stringify({ type: "sdp_offer", data: offer }));
}

async function startIngressConnection(channel, topic) {
  videoPlayer.srcObject = new MediaStream();

  const pc = new RTCPeerConnection(pcConfig);
  pc.ontrack = (event) => videoPlayer.srcObject.addTrack(event.track);
  pc.onicecandidate = (event) => {
    if (event.candidate === null) return;

    console.log("Sent ICE candidate:", event.candidate);
    channel.push(topic, JSON.stringify({ type: "ice_candidate", data: event.candidate }));
  };

  channel.on(topic, async (payload) => {
    type = payload.type;
    data = payload.data;

    switch (type) {
      case "sdp_offer":
        console.log("Received SDP offer:", data);
        await pc.setRemoteDescription(data);
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        channel.push(topic, JSON.stringify({ type: "sdp_answer", data: answer }));
        console.log("Sent SDP answer:", answer);
        break;
      case "ice_candidate":
        console.log("Received ICE candidate:", data);
        await pc.addIceCandidate(data);
    }
  });
}
const videoPlayer = document.getElementById("videoPlayer");
const signalingId = videoPlayer.getAttribute("signaling_id");

let socket = new Socket("/signaling", { params: { token: window.userToken } });
socket.connect();
let egressChannel = socket.channel(`${signalingId}_egress`);
egressChannel
  .join()
  .receive("ok", (resp) => {
    console.log("Joined successfully to egress signaling socket", resp);
    startEgressConnection(egressChannel, `${signalingId}_egress`);
  })
  .receive("error", (resp) => {
    console.log("Unable to join egress signaling socket", resp);
  });

const pcConfig = { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };

let ingressChannel = socket.channel(`${signalingId}_ingress`);
ingressChannel
  .join()
  .receive("ok", (resp) => {
    console.log("Joined successfully to ingress signaling socket", resp);
    startIngressConnection(ingressChannel, `${signalingId}_ingress`);
  })
  .receive("error", (resp) => {
    console.log("Unable to join ingress signaling socket", resp);
  });
