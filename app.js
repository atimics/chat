// Matrix Web Client with Crypto Authentication
class MatrixCryptoClient {
    constructor() {
        this.web3 = null;
        this.account = null;
        this.matrixClient = null;
        this.currentRoom = null;
        this.approvedWallets = [];
        this.init();
    }

    async init() {
        // Load approved wallets from userlist
        await this.loadApprovedWallets();
        this.setupEventListeners();
    }

    async loadApprovedWallets() {
        try {
            const response = await fetch('/api/approved-wallets');
            const data = await response.json();
            this.approvedWallets = data.wallets || [];
        } catch (error) {
            console.error('Error loading approved wallets:', error);
            // Fallback to mock data for development
            this.approvedWallets = [
                '0x742d35Cc6634C0532925a3b8D0e8c4e2d8c71a8B',
                '0x8ba1f109551bD432803012645Hac136c1C0F9Ba8',
                '0x1234567890123456789012345678901234567890'
            ];
        }
    }

    setupEventListeners() {
        document.getElementById('sign-btn').addEventListener('click', () => this.signAuthMessage());
        document.getElementById('logout-btn').addEventListener('click', () => this.logout());
        document.getElementById('send-btn').addEventListener('click', () => this.sendMessage());
        document.getElementById('message-input').addEventListener('keypress', (e) => {
            if (e.key === 'Enter') this.sendMessage();
        });
    }

    async connectWallet(walletType) {
        try {
            if (typeof window.ethereum !== 'undefined') {
                this.web3 = new Web3(window.ethereum);
                
                // Request account access
                const accounts = await window.ethereum.request({ 
                    method: 'eth_requestAccounts' 
                });
                
                this.account = accounts[0];
                
                // Check if wallet is approved
                if (!this.isWalletApproved(this.account)) {
                    this.showError('Wallet not approved for registration');
                    return;
                }
                
                // Show wallet status
                this.showWalletConnected();
                
            } else {
                this.showError('MetaMask is not installed');
            }
        } catch (error) {
            console.error('Error connecting wallet:', error);
            this.showError('Failed to connect wallet');
        }
    }

    isWalletApproved(address) {
        return this.approvedWallets.some(wallet => 
            wallet.toLowerCase() === address.toLowerCase()
        );
    }

    showWalletConnected() {
        document.getElementById('wallet-status').classList.remove('hidden');
        document.getElementById('wallet-address').textContent = 
            `${this.account.slice(0, 6)}...${this.account.slice(-4)}`;
    }

    async signAuthMessage() {
        try {
            const message = `Authenticate to Chatimics Matrix Server\nWallet: ${this.account}\nTimestamp: ${Date.now()}`;
            
            const signature = await this.web3.eth.personal.sign(message, this.account);
            
            // Verify signature and authenticate with Matrix
            await this.authenticateWithMatrix(this.account, signature, message);
            
        } catch (error) {
            console.error('Error signing message:', error);
            this.showError('Failed to sign authentication message');
        }
    }

    async authenticateWithMatrix(address, signature, message) {
        try {
            // Send authentication request to backend
            const response = await fetch('/api/authenticate', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    address,
                    signature,
                    message
                })
            });

            const authData = await response.json();
            
            if (!response.ok) {
                throw new Error(authData.error || 'Authentication failed');
            }

            // Initialize Matrix client with credentials
            this.matrixClient = matrixcs.createClient({
                baseUrl: authData.serverUrl,
                accessToken: null,
                userId: null
            });

            // Login to Matrix
            try {
                const loginResponse = await this.matrixClient.login('m.login.password', {
                    user: authData.matrixUsername,
                    password: authData.matrixPassword
                });

                // Start the client
                await this.matrixClient.startClient();
                
                // Show Matrix client interface
                this.showMatrixClient(authData.matrixUsername);
                
            } catch (loginError) {
                console.log('Login failed, attempting registration...');
                await this.registerMatrixUser(address, signature, message);
            }
            
        } catch (error) {
            console.error('Matrix authentication failed:', error);
            this.showError(error.message || 'Authentication failed');
        }
    }

    getMatrixUsername(address) {
        // Generate username from wallet address
        return `crypto_${address.slice(2, 10).toLowerCase()}`;
    }

    getMatrixPassword(address) {
        // Generate password from wallet address (in production, use proper password generation)
        return `pwd_${address.slice(-8)}`;
    }

    async registerMatrixUser(address, signature, message) {
        try {
            const username = this.getMatrixUsername(address);
            const password = this.getMatrixPassword(address);
            
            // Register new user
            const registerResponse = await this.matrixClient.register(
                username,
                password,
                null, // session_id
                null, // auth
                null, // bind_email
                null, // bind_msisdn
                null  // inhibit_login
            );

            // Start the client after registration
            await this.matrixClient.startClient();
            
            this.showMatrixClient(username);
            
        } catch (error) {
            console.error('Matrix registration failed:', error);
            this.showError('Failed to register with Matrix server');
        }
    }

    showMatrixClient(username) {
        // Hide auth section
        document.getElementById('auth-section').classList.add('hidden');
        
        // Show matrix client
        document.getElementById('matrix-client').classList.remove('hidden');
        document.getElementById('user-info').textContent = `@${username}:chat.ratimics.com`;
        
        // Setup Matrix event listeners
        this.setupMatrixEventListeners();
        
        // Load rooms
        this.loadRooms();
    }

    setupMatrixEventListeners() {
        if (!this.matrixClient) return;

        this.matrixClient.on('Room.timeline', (event, room, toStartOfTimeline) => {
            if (toStartOfTimeline) return;
            if (room.roomId === this.currentRoom?.roomId) {
                this.displayMessage(event);
            }
        });

        this.matrixClient.on('sync', (state) => {
            if (state === 'PREPARED') {
                this.loadRooms();
            }
        });
    }

    loadRooms() {
        if (!this.matrixClient) return;

        const rooms = this.matrixClient.getRooms();
        const roomList = document.getElementById('room-list');
        roomList.innerHTML = '';

        rooms.forEach(room => {
            const roomElement = document.createElement('div');
            roomElement.className = 'p-3 rounded-lg bg-white bg-opacity-10 cursor-pointer hover:bg-opacity-20 transition-all';
            roomElement.innerHTML = `
                <div class="text-white font-medium">${room.name || 'Unnamed Room'}</div>
                <div class="text-gray-300 text-sm">${room.getJoinedMemberCount()} members</div>
            `;
            roomElement.addEventListener('click', () => this.selectRoom(room));
            roomList.appendChild(roomElement);
        });
    }

    selectRoom(room) {
        this.currentRoom = room;
        this.loadMessages();
        
        // Update room selection UI
        document.querySelectorAll('#room-list > div').forEach(el => {
            el.classList.remove('bg-blue-600');
        });
        event.currentTarget.classList.add('bg-blue-600');
    }

    loadMessages() {
        if (!this.currentRoom) return;

        const chatMessages = document.getElementById('chat-messages');
        chatMessages.innerHTML = '';

        const timeline = this.currentRoom.timeline;
        timeline.forEach(event => {
            if (event.getType() === 'm.room.message') {
                this.displayMessage(event);
            }
        });

        chatMessages.scrollTop = chatMessages.scrollHeight;
    }

    displayMessage(event) {
        if (event.getType() !== 'm.room.message') return;

        const chatMessages = document.getElementById('chat-messages');
        const messageElement = document.createElement('div');
        messageElement.className = 'mb-4';
        
        const sender = event.getSender();
        const content = event.getContent();
        const timestamp = new Date(event.getTs()).toLocaleTimeString();

        messageElement.innerHTML = `
            <div class="flex items-start space-x-3">
                <div class="w-8 h-8 bg-gradient-to-r from-blue-400 to-purple-500 rounded-full flex items-center justify-center text-white text-sm font-bold">
                    ${sender.charAt(1).toUpperCase()}
                </div>
                <div class="flex-1">
                    <div class="flex items-center space-x-2 mb-1">
                        <span class="text-white font-medium">${sender}</span>
                        <span class="text-gray-400 text-xs">${timestamp}</span>
                    </div>
                    <div class="text-gray-200">${content.body}</div>
                </div>
            </div>
        `;

        chatMessages.appendChild(messageElement);
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }

    async sendMessage() {
        const messageInput = document.getElementById('message-input');
        const message = messageInput.value.trim();
        
        if (!message || !this.currentRoom || !this.matrixClient) return;

        try {
            await this.matrixClient.sendTextMessage(this.currentRoom.roomId, message);
            messageInput.value = '';
        } catch (error) {
            console.error('Error sending message:', error);
            this.showError('Failed to send message');
        }
    }

    logout() {
        if (this.matrixClient) {
            this.matrixClient.logout();
            this.matrixClient.stopClient();
        }
        
        this.account = null;
        this.matrixClient = null;
        this.currentRoom = null;
        
        // Show auth section
        document.getElementById('auth-section').classList.remove('hidden');
        document.getElementById('matrix-client').classList.add('hidden');
        document.getElementById('wallet-status').classList.add('hidden');
    }

    showError(message) {
        // Create error notification
        const errorDiv = document.createElement('div');
        errorDiv.className = 'fixed top-4 right-4 bg-red-500 text-white px-6 py-3 rounded-lg shadow-lg z-50';
        errorDiv.innerHTML = `
            <div class="flex items-center">
                <i class="fas fa-exclamation-triangle mr-2"></i>
                <span>${message}</span>
            </div>
        `;
        
        document.body.appendChild(errorDiv);
        
        setTimeout(() => {
            errorDiv.remove();
        }, 5000);
    }
}

// Global functions for wallet connection
window.connectWallet = function(walletType) {
    window.matrixCryptoClient.connectWallet(walletType);
};

// Initialize the application
window.addEventListener('DOMContentLoaded', () => {
    window.matrixCryptoClient = new MatrixCryptoClient();
});
