#!/usr/bin/env node

const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3001; // Changed to 3001 to avoid conflict with Next.js

// Middleware
app.use(cors());
app.use(express.json());

// Neynar API configuration for Farcaster
const NEYNAR_API_KEY = process.env.NEYNAR_API_KEY || 'your-neynar-api-key';
const NEYNAR_BASE_URL = 'https://api.neynar.com/v2';

// Load approved wallets and Farcaster users from userlist.txt
function loadApprovedUsers() {
    try {
        const userlistPath = path.join(__dirname, 'userlist.txt');
        const userlistContent = fs.readFileSync(userlistPath, 'utf8');
        const lines = userlistContent.split('\n').filter(line => line.trim());
        
        const users = [];
        lines.forEach(line => {
            const parts = line.trim().split(/\s+/);
            if (parts.length >= 2) {
                const username = parts[0];
                const token = parts[1];
                
                // Generate a mock wallet address based on username for demo
                const hash = crypto.createHash('sha256').update(username).digest('hex');
                const mockWallet = '0x' + hash.substring(0, 40);
                
                users.push({
                    username,
                    wallet: mockWallet,
                    token,
                    // For Farcaster, we'll use username as FID for demo
                    farcasterFid: username === 'ratimics' ? 12345 : Math.floor(Math.random() * 100000),
                    farcasterUsername: username
                });
            }
        });
        
        return users;
    } catch (error) {
        console.error('Error loading approved users:', error);
        return [];
    }
}

// Verify wallet signature
function verifyWalletSignature(address, signature, message) {
    try {
        const recoveredAddress = ethers.utils.verifyMessage(message, signature);
        return recoveredAddress.toLowerCase() === address.toLowerCase();
    } catch (error) {
        console.error('Error verifying signature:', error);
        return false;
    }
}

// Verify Farcaster user with Neynar API
async function verifyFarcasterUser(fid) {
    try {
        const response = await axios.get(`${NEYNAR_BASE_URL}/farcaster/user`, {
            params: { fid },
            headers: {
                'Accept': 'application/json',
                'api_key': NEYNAR_API_KEY
            }
        });
        return response.data;
    } catch (error) {
        console.error('Error verifying Farcaster user:', error);
        return null;
    }
}

// Generate Matrix credentials
function generateMatrixCredentials(identifier, authMethod) {
    const prefix = authMethod === 'farcaster' ? 'fc' : 'crypto';
    const hash = crypto.createHash('sha256').update(identifier).digest('hex').substring(0, 8);
    
    return {
        matrixUsername: `${prefix}_${hash}`,
        matrixPassword: `pwd_${hash}`,
        serverUrl: 'https://chat.ratimics.com'
    };
}

// API Routes
app.get('/api/approved-wallets', (req, res) => {
    const users = loadApprovedUsers();
    const wallets = users.map(u => u.wallet);
    res.json({ wallets });
});

app.get('/api/approved-farcaster-users', (req, res) => {
    const users = loadApprovedUsers();
    const farcasterUsers = users.map(u => ({
        fid: u.farcasterFid,
        username: u.farcasterUsername
    }));
    res.json({ users: farcasterUsers });
});

app.post('/api/authenticate', async (req, res) => {
    try {
        const { address, signature, message, farcasterProfile, authMethod } = req.body;
        
        if (!authMethod) {
            return res.status(400).json({ error: 'Authentication method required' });
        }

        const approvedUsers = loadApprovedUsers();
        let approvedUser = null;
        let credentials = null;

        if (authMethod === 'wallet') {
            if (!address || !signature || !message) {
                return res.status(400).json({ error: 'Missing required wallet fields' });
            }
            
            // Find approved wallet
            approvedUser = approvedUsers.find(u => 
                u.wallet.toLowerCase() === address.toLowerCase()
            );
            
            if (!approvedUser) {
                return res.status(403).json({ error: 'Wallet not approved' });
            }
            
            // Verify signature
            if (!verifyWalletSignature(address, signature, message)) {
                return res.status(401).json({ error: 'Invalid signature' });
            }
            
            credentials = generateMatrixCredentials(address, 'wallet');
            
        } else if (authMethod === 'farcaster') {
            if (!farcasterProfile || !farcasterProfile.fid) {
                return res.status(400).json({ error: 'Missing Farcaster profile' });
            }
            
            // Find approved Farcaster user
            approvedUser = approvedUsers.find(u => 
                u.farcasterUsername.toLowerCase() === farcasterProfile.username?.toLowerCase() ||
                u.farcasterFid === farcasterProfile.fid
            );
            
            if (!approvedUser) {
                return res.status(403).json({ error: 'Farcaster user not approved' });
            }
            
            // Optional: Verify with Neynar API
            // const farcasterData = await verifyFarcasterUser(farcasterProfile.fid);
            // if (!farcasterData) {
            //     return res.status(401).json({ error: 'Invalid Farcaster profile' });
            // }
            
            credentials = generateMatrixCredentials(farcasterProfile.fid.toString(), 'farcaster');
        }
        
        res.json({
            success: true,
            ...credentials,
            authMethod,
            approvedUser: {
                username: approvedUser.username,
                authMethod
            }
        });
        
    } catch (error) {
        console.error('Authentication error:', error);
        res.status(500).json({ error: 'Authentication failed' });
    }
});

app.post('/api/send-message', async (req, res) => {
    try {
        const { roomId, message, credentials } = req.body;
        
        // Here you would integrate with Matrix SDK to send the message
        // For now, we'll return a success response
        
        console.log(`Message from ${credentials.matrixUsername} in ${roomId}: ${message}`);
        
        res.json({
            success: true,
            messageId: Date.now().toString(),
            timestamp: Date.now()
        });
        
    } catch (error) {
        console.error('Send message error:', error);
        res.status(500).json({ error: 'Failed to send message' });
    }
});

app.post('/api/register-matrix-user', async (req, res) => {
    try {
        const { username, password, walletAddress, farcasterProfile } = req.body;
        
        // Here you would integrate with Matrix registration API
        // For now, we'll return a success response
        
        res.json({
            success: true,
            message: 'User registered successfully',
            username,
            homeserver: 'https://chat.ratimics.com'
        });
        
    } catch (error) {
        console.error('Registration error:', error);
        res.status(500).json({ error: 'Registration failed' });
    }
});

// Health check
app.get('/health', (req, res) => {
    res.json({ 
        status: 'OK', 
        timestamp: new Date().toISOString(),
        service: 'Chatimics Matrix API'
    });
});

// Get user stats
app.get('/api/stats', (req, res) => {
    const users = loadApprovedUsers();
    res.json({
        totalApprovedUsers: users.length,
        walletUsers: users.length,
        farcasterUsers: users.filter(u => u.farcasterUsername).length,
        timestamp: new Date().toISOString()
    });
});

app.listen(PORT, () => {
    console.log(`🚀 Chatimics Matrix API server running on port ${PORT}`);
    console.log(`📊 Health check: http://localhost:${PORT}/health`);
    console.log(`📈 Stats: http://localhost:${PORT}/api/stats`);
    console.log(`💼 Approved wallets: http://localhost:${PORT}/api/approved-wallets`);
    console.log(`🟣 Farcaster users: http://localhost:${PORT}/api/approved-farcaster-users`);
});
