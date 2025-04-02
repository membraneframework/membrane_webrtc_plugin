export function createPlayerHook(iceServers = [{ urls: `stun:stun.l.google.com:19302` }]) {
  return {
    async mounted() {
      this.pc = new RTCPeerConnection({ iceServers: iceServers });
      this.el.srcObject = new MediaStream();

      this.pc.ontrack = (event) => {
        this.el.srcObject.addTrack(event.track);
      };

      this.pc.onicecandidate = (ev) => {
        console.log(`[${this.el.id}] Sent ICE candidate:`, ev.candidate);
        message = { type: `ice_candidate`, data: ev.candidate };
        this.pushEventTo(this.el, `webrtc_signaling`, message);
      };

      const eventName = `webrtc_signaling-${this.el.id}`;
      this.handleEvent(eventName, async (event) => {
        const { type, data } = event;

        switch (type) {
          case `sdp_offer`:
            console.log(`[${this.el.id}] Received SDP offer:`, data);
            await this.pc.setRemoteDescription(data);

            const answer = await this.pc.createAnswer();
            await this.pc.setLocalDescription(answer);

            message = { type: `sdp_answer`, data: answer };
            this.pushEventTo(this.el, `webrtc_signaling`, message);
            console.log(`[${this.el.id}] Sent SDP answer:`, answer);

            break;
          case `ice_candidate`:
            console.log(`[${this.el.id}] Received ICE candidate:`, data);
            await this.pc.addIceCandidate(data);
        }
      });
    },
  };
}
