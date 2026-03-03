import { getRdpClient } from "./rdp-integration.js";

(async () => {
    const rdpClient = await getRdpClient();
    if(rdpClient) {
        window.challenge.setRdpClient(rdpClient);
    }

})();
