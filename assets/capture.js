export function createCaptureHook(iceServers = [{ urls: `stun:stun.l.google.com:19302` }]) {
  return {
    async mounted() {
      this.handleEvent(`media_constraints-${this.el.id}`, async (mediaConstraints) => {
        console.log(`[${this.el.id}] Received media constraints:`, mediaConstraints);

        const localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
        const pcConfig = { iceServers: iceServers };
        this.pc = new RTCPeerConnection(pcConfig);

        this.pc.onicecandidate = (event) => {
          if (event.candidate === null) return;
          console.log(`[${this.el.id}] Sent ICE candidate:`, event.candidate);
          message = { type: `ice_candidate`, data: event.candidate };
          this.pushEventTo(this.el, `webrtc_signaling`, message);
        };

        this.pc.onconnectionstatechange = () => {
          console.log(
            `[${this.el.id}] RTCPeerConnection state changed to`,
            this.pc.connectionState
          );
        };

        this.el.srcObject = new MediaStream();

        for (const track of localStream.getTracks()) {
          this.pc.addTrack(track, localStream);
          this.el.srcObject.addTrack(track);
        }

        this.el.play();

        this.handleEvent(`webrtc_signaling-${this.el.id}`, async (event) => {
          const { type, data } = event;

          switch (type) {
            case `sdp_answer`:
              console.log(`[${this.el.id}] Received SDP answer:`, data);
              await this.pc.setRemoteDescription(data);
              break;
            case `ice_candidate`:
              console.log(`[${this.el.id}] Received ICE candidate:`, data);
              await this.pc.addIceCandidate(data);
              break;
          }
        });

        const offer = await this.pc.createOffer();
        await this.pc.setLocalDescription(offer);
        console.log(`[${this.el.id}] Sent SDP offer:`, offer);
        message = { type: `sdp_offer`, data: offer };
        this.pushEventTo(this.el, `webrtc_signaling`, message);
      });
    },
  };
}
