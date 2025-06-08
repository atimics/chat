# 🚀 Chatimics Matrix Web Client

A modern, secure Matrix web client with **multi-wallet authentication** and **Farcaster integration**. Built with Next.js, RainbowKit, and TypeScript.

## ✨ Features

### 🔐 Multi-Wallet Authentication
- **RainbowKit Integration**: Supports 100+ wallets including MetaMask, WalletConnect, Coinbase, and more
- **Cryptographic Authentication**: Users sign messages with their wallet to prove ownership
- **Approved Wallet Validation**: Only pre-approved wallets can access the chat

### 🟣 Farcaster Integration
- **Social Authentication**: Sign in with your Farcaster account
- **Profile Integration**: Display Farcaster usernames and profile data
- **Seamless Experience**: One-click authentication for Farcaster users

### 💬 Matrix Chat Features
- **Real-time Messaging**: Powered by Matrix protocol
- **Multiple Rooms**: Support for different chat channels
- **Modern UI**: Glass-morphism design with smooth animations
- **Responsive Design**: Works on desktop and mobile

## Quick Start

### Option 1: Using the Setup Script

```bash
./setup_web_client.sh
npm start
```

### Option 2: Manual Setup

```bash
# Install dependencies
npm install

# Start the server
npm start
```

### Option 3: Using Docker

```bash
# Build and run with docker-compose
docker-compose up -d webclient
```

The web client will be available at `http://localhost:3000`

## Configuration

### Approved Wallets

The system reads approved wallet addresses from `userlist.txt`. The format is:
```
username    password/token    approved_status
```

The server generates wallet addresses based on usernames for validation.

### Environment Variables

Create a `.env` file with:
```
PORT=3000
MATRIX_SERVER_URL=https://chat.ratimics.com
NODE_ENV=development
```

## How It Works

1. **Wallet Connection**: User connects their crypto wallet (MetaMask, etc.)
2. **Validation**: System checks if wallet is in approved list
3. **Signature**: User signs authentication message with their wallet
4. **Verification**: Server verifies the cryptographic signature
5. **Matrix Auth**: System generates Matrix credentials and logs user in
6. **Chat Access**: User can now access Matrix rooms and chat

## API Endpoints

- `GET /api/approved-wallets` - Returns list of approved wallet addresses
- `POST /api/authenticate` - Authenticates wallet signature and returns Matrix credentials
- `POST /api/register-matrix-user` - Registers new Matrix user (if needed)

## Development

```bash
# Install development dependencies
npm install

# Start development server with auto-reload
npm run dev
```

## File Structure

```
├── index.html          # Main web interface
├── app.js              # Frontend JavaScript (Matrix + Crypto)
├── server.js           # Backend API server
├── package.json        # Node.js dependencies
├── Dockerfile.webclient # Docker configuration
└── setup_web_client.sh # Setup script
```

## Security Notes

- Wallet signatures are verified cryptographically
- Only approved wallets can access the system
- Matrix passwords are generated from wallet addresses
- All communications use HTTPS in production

## Requirements

- Node.js 16+
- Matrix Synapse server
- MetaMask or compatible wallet for users
- Modern web browser with Web3 support

## Troubleshooting

**Wallet not connecting?**
- Ensure MetaMask is installed and unlocked
- Check browser console for errors
- Verify wallet is on correct network

**Authentication failing?**
- Confirm wallet address is in approved list
- Check Matrix server is accessible
- Verify signature is being generated correctly

**Matrix rooms not loading?**
- Ensure Matrix server is running
- Check homeserver.yaml configuration
- Verify user has proper permissions
