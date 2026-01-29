import { RDPClient } from '../../freerdp-web/rdp-client.js';


export async function getRdpClient(element = null, connectBtn = null) {
    if(connectBtn === undefined || connectBtn === null) {
        connectBtn = document.getElementById('rdpConnectBtn');
    }
    if(element === undefined || element === null) {
        element = document.getElementById('rdpContainer');
    }
    if(!(element instanceof HTMLElement)) {
        throw new Error('Invalid element provided to getRdpClient');
    }
    const response = await fetch('/api/get/rdp-connection');
    if (!response.ok) {
        throw new Error('Network response was not ok from /api/get/rdp-connection');
    }
    const info = await response.json();

    if (!Array.isArray(info.endpoints)) {
        throw new Error('Invalid Response from /api/get/rdp-connection');
    }

    if(info.endpoints.length === 0) {
        console.warn('No RDP WebSocket endpoints available to test. This can be normal, if RDP integration is not enabled.');
        return null;
    }

    // connection info must be present
    if(!info.connection || !info.connection.host || !info.connection.port || !info.connection.user || !info.connection.pass) {
        console.warn('Incomplete RDP connection info received. Cannot connect to RDP session.');
        return null;
    }

    // pick a random endpoint from the list
    const wsUrl = info.endpoints[Math.floor(Math.random() * info.endpoints.length)];

    const client = new RDPClient(
        element,
        {
            wsUrl: wsUrl,
            showTopBar: false,
            showBottomBar: false,
            loadingSpinnerOpensModal: false,
            theme: { 
                preset: 'light'
            }
        }
    );

    await client.connect({
        host: info.connection.host,
        port: info.connection.port,
        user: info.connection.user,
        pass: info.connection.pass
    });

    if(!client.isConnected()) {
        console.warn('Failed to connect to RDP session');
        return null;
    }

    let reconnectTriggered = false;

    if(connectBtn) {
        connectBtn.addEventListener('click', async() => {
            reconnectTriggered = true;
            if(client.isConnected()) {
                await client.disconnect();
            }
            // sleep 500ms
            await new Promise(resolve => setTimeout(resolve, 500));
            await client.connect({
                host: info.connection.host,
                port: info.connection.port,
                user: info.connection.user,
                pass: info.connection.pass
            });
        });
    }

    client.on('connected', async() => {
        if(connectBtn) {
            connectBtn.disabled = false;
        }
        
    });
    client.on('disconnected', () => {
        if(connectBtn) {
            connectBtn.disabled = false;
            setTimeout(() => {
                if(!client.isConnected()) {
                    connectBtn.disabled = false;
                }
            }, 60000); // re-enable after 60 seconds
        }
        if(!reconnectTriggered) {
            exponentialBackoffReconnect(client, info);
        }
        reconnectTriggered = false;
    });

    return client;
}



function exponentialBackoffReconnect(client, info, maxAttempts = 5, attempt = 1) {
    const delay = Math.min(30000, Math.pow(2, attempt) * 250); // Exponential backoff with max delay of 30 seconds

    console.log(`RDP disconnected. Attempting to reconnect in ${delay / 1000} seconds... (Attempt ${attempt} of ${maxAttempts})`);

    setTimeout(async () => {
        try {
            await client.connect({
                            host: info.connection.host,
                            port: info.connection.port,
                            user: info.connection.user,
                            pass: info.connection.pass
                        });
            if (client.isConnected()) {
                console.log('RDP reconnected successfully.');
                return;
            }
        } catch (error) {
            console.error('RDP reconnection attempt failed:', error);
        }
        if (attempt < maxAttempts) {
            exponentialBackoffReconnect(client, info, maxAttempts, attempt + 1);
        } else {
            console.error('Max RDP reconnection attempts reached. Giving up.');
        }
    }, delay);
}
