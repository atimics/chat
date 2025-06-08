# NFT-Based Authentication System for Matrix Synapse

## Overview

This system extends your existing Matrix Synapse homeserver with Solana NFT-based authentication. Users can register if they hold NFTs created by specified Solana wallets.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Web Client    │────│  Auth Middleware │────│ Matrix Synapse  │
│  (Next.js +     │    │   (Express.js)   │    │   Homeserver    │
│   Solana SDK)   │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌────────▼────────┐             │
         │              │  NFT Validator  │             │
         │              │   (Helius API)  │             │
         │              └─────────────────┘             │
         │                                              │
         └──────────────────┐                          │
                           ▼                          │
                ┌─────────────────┐                   │
                │ Registration DB │◄──────────────────┘
                │   (SQLite)      │
                └─────────────────┘
```

## Features

### ✅ NFT-Based Registration
- Verify NFT ownership on Solana blockchain
- Support for multiple authorized creator wallets
- Automatic Matrix user creation upon verification

### ✅ Security Features
- Wallet signature verification
- Rate limiting for registration attempts
- Secure credential generation
- Audit logging

### ✅ Integration
- Seamless integration with existing Matrix Synapse setup
- Compatible with current authentication methods
- No disruption to existing users

## Configuration Files

### `.env` Configuration
```bash
# Solana Configuration
SOLANA_RPC_URL=https://api.mainnet-beta.solana.com
HELIUS_API_KEY=your_helius_api_key_here

# NFT Creator Wallets (comma-separated)
AUTHORIZED_NFT_CREATORS=7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU,AnotherCreatorWallet123

# Matrix Synapse Configuration  
MATRIX_SERVER_URL=https://chat.ratimics.com
SYNAPSE_ADMIN_TOKEN=your_synapse_admin_token

# Database
NFT_AUTH_DB_PATH=./nft_auth_system/data/nft_registrations.db
```

## Components

1. **NFT Verification Service** - Validates NFT ownership
2. **Registration API** - Handles user registration workflow
3. **Matrix Integration** - Creates users in Synapse
4. **Web Interface** - User-friendly registration flow
5. **Admin Dashboard** - Manage authorized creators and users
