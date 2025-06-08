#!/usr/bin/env node

/**
 * NFT-Based Authentication Service for Matrix Synapse
 * Handles wallet verification, NFT ownership validation, and user registration
 */

const express = require('express');
const cors = require('cors');
const sqlite3 = require('sqlite3').verbose();
const crypto = require('crypto');
const axios = require('axios');
const { Connection, clusterApiUrl, PublicKey } = require('@solana/web3.js');
const { Metaplex } = require('@metaplex-foundation/js');
const nacl = require('tweetnacl');
const bs58 = require('bs58');
const rateLimit = require('express-rate-limit');

const app = express();
const PORT = process.env.NFT_AUTH_PORT || 3002;

// Environment variables
const SOLANA_RPC_URL = process.env.SOLANA_RPC_URL || 'https://api.mainnet-beta.solana.com';
const HELIUS_API_KEY = process.env.HELIUS_API_KEY;
const MATRIX_SERVER_URL = process.env.MATRIX_SERVER_URL || 'https://chat.ratimics.com';
const SYNAPSE_ADMIN_TOKEN = process.env.SYNAPSE_ADMIN_TOKEN;
const AUTHORIZED_NFT_CREATORS = (process.env.AUTHORIZED_NFT_CREATORS || '').split(',').filter(Boolean);
const NFT_AUTH_DB_PATH = process.env.NFT_AUTH_DB_PATH || './nft_auth_system/data/nft_registrations.db';
const MAIN_ROOM_ID = process.env.MAIN_ROOM_ID || '!main:chat.ratimics.com';

// Middleware
app.use(cors());
app.use(express.json());

// Rate limiting
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // limit each IP to 5 requests per windowMs
  message: { error: 'Too many authentication attempts, please try again later.' }
});

app.use('/auth', authLimiter);

// Initialize Solana connection
const connection = new Connection(SOLANA_RPC_URL);
const metaplex = Metaplex.make(connection);

// Initialize SQLite database
let db;
function initDatabase() {
  return new Promise((resolve, reject) => {
    db = new sqlite3.Database(NFT_AUTH_DB_PATH, (err) => {
      if (err) {
        console.error('Error opening database:', err);
        reject(err);
      } else {
        console.log('Connected to SQLite database');
        createTables().then(resolve).catch(reject);
      }
    });
  });
}

function createTables() {
  return new Promise((resolve, reject) => {
    const createRegistrationsTable = `
      CREATE TABLE IF NOT EXISTS nft_registrations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wallet_address TEXT UNIQUE NOT NULL,
        matrix_user_id TEXT UNIQUE NOT NULL,
        pseudonym TEXT NOT NULL,
        nft_mint_address TEXT NOT NULL,
        nft_creator_address TEXT NOT NULL,
        registration_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_verified DATETIME DEFAULT CURRENT_TIMESTAMP,
        is_active BOOLEAN DEFAULT TRUE,
        temp_password TEXT NOT NULL
      );
    `;

    const createNoncesTable = `
      CREATE TABLE IF NOT EXISTS auth_nonces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nonce TEXT UNIQUE NOT NULL,
        wallet_address TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        used BOOLEAN DEFAULT FALSE
      );
    `;

    db.run(createRegistrationsTable, (err) => {
      if (err) {
        reject(err);
      } else {
        db.run(createNoncesTable, (err) => {
          if (err) {
            reject(err);
          } else {
            resolve();
          }
        });
      }
    });
  });
}

// Utility functions
function generatePseudonym(walletAddress) {
  // Create a pseudonym based on wallet address
  const hash = crypto.createHash('sha256').update(walletAddress).digest('hex');
  const adjectives = ['Cosmic', 'Quantum', 'Digital', 'Cyber', 'Neural', 'Virtual', 'Mystic', 'Stellar', 'Neon', 'Crypto'];
  const nouns = ['Wanderer', 'Pioneer', 'Explorer', 'Dreamer', 'Seeker', 'Voyager', 'Oracle', 'Guardian', 'Sage', 'Navigator'];
  
  const adjIndex = parseInt(hash.substring(0, 2), 16) % adjectives.length;
  const nounIndex = parseInt(hash.substring(2, 4), 16) % nouns.length;
  const numSuffix = parseInt(hash.substring(4, 8), 16) % 10000;
  
  return `${adjectives[adjIndex]}${nouns[nounIndex]}${numSuffix}`;
}

function generateMatrixUserId(pseudonym) {
  // Convert pseudonym to lowercase and replace spaces with underscores
  const username = pseudonym.toLowerCase().replace(/\s+/g, '_');
  return `@${username}:chat.ratimics.com`;
}

function generateSecurePassword() {
  return crypto.randomBytes(16).toString('base64');
}

function generateNonce() {
  return crypto.randomBytes(32).toString('hex');
}

// NFT Verification Functions
async function verifyNFTOwnership(walletAddress, authorizedCreators) {
  try {
    console.log(`Verifying NFT ownership for wallet: ${walletAddress}`);
    
    // Get all NFTs owned by the wallet using Helius API
    const response = await axios.get(`https://api.helius.xyz/v0/addresses/${walletAddress}/nfts`, {
      params: {
        'api-key': HELIUS_API_KEY
      }
    });

    const nfts = response.data;
    
    // Check if any NFT is created by authorized creators
    for (const nft of nfts) {
      const creators = nft.creators || [];
      for (const creator of creators) {
        if (authorizedCreators.includes(creator.address) && creator.verified) {
          console.log(`Found qualifying NFT: ${nft.mint} by creator: ${creator.address}`);
          return {
            isValid: true,
            nft: {
              mint: nft.mint,
              creator: creator.address,
              name: nft.name || 'Unknown NFT',
              image: nft.image || null
            }
          };
        }
      }
    }

    return { isValid: false, nft: null };
  } catch (error) {
    console.error('Error verifying NFT ownership:', error);
    return { isValid: false, nft: null, error: error.message };
  }
}

async function verifyWalletSignature(walletAddress, signature, message) {
  try {
    const publicKey = new PublicKey(walletAddress);
    const messageBytes = new TextEncoder().encode(message);
    const signatureBytes = bs58.decode(signature);
    
    const isValid = nacl.sign.detached.verify(messageBytes, signatureBytes, publicKey.toBytes());
    return isValid;
  } catch (error) {
    console.error('Error verifying wallet signature:', error);
    return false;
  }
}

// Matrix Synapse Integration
async function createMatrixUser(userId, password, displayName) {
  try {
    const response = await axios.put(
      `${MATRIX_SERVER_URL}/_synapse/admin/v2/users/${encodeURIComponent(userId)}`,
      {
        password: password,
        displayname: displayName,
        admin: false,
        deactivated: false
      },
      {
        headers: {
          'Authorization': `Bearer ${SYNAPSE_ADMIN_TOKEN}`,
          'Content-Type': 'application/json'
        }
      }
    );

    console.log(`Created Matrix user: ${userId}`);
    return { success: true, data: response.data };
  } catch (error) {
    console.error('Error creating Matrix user:', error.response?.data || error.message);
    return { success: false, error: error.response?.data || error.message };
  }
}

async function inviteUserToMainRoom(userId) {
  try {
    const response = await axios.post(
      `${MATRIX_SERVER_URL}/_matrix/client/r0/rooms/${encodeURIComponent(MAIN_ROOM_ID)}/invite`,
      {
        user_id: userId
      },
      {
        headers: {
          'Authorization': `Bearer ${SYNAPSE_ADMIN_TOKEN}`,
          'Content-Type': 'application/json'
        }
      }
    );

    console.log(`Invited user ${userId} to main room`);
    return { success: true };
  } catch (error) {
    console.error('Error inviting user to main room:', error.response?.data || error.message);
    return { success: false, error: error.response?.data || error.message };
  }
}

// API Routes

// Generate authentication nonce
app.post('/auth/nonce', async (req, res) => {
  try {
    const { walletAddress } = req.body;

    if (!walletAddress) {
      return res.status(400).json({ error: 'Wallet address is required' });
    }

    // Validate wallet address format
    try {
      new PublicKey(walletAddress);
    } catch (error) {
      return res.status(400).json({ error: 'Invalid wallet address format' });
    }

    const nonce = generateNonce();
    
    // Store nonce in database
    db.run(
      'INSERT INTO auth_nonces (nonce, wallet_address) VALUES (?, ?)',
      [nonce, walletAddress],
      function(err) {
        if (err) {
          console.error('Error storing nonce:', err);
          return res.status(500).json({ error: 'Failed to generate nonce' });
        }

        res.json({ 
          nonce,
          message: `Sign this message to authenticate with Chatimics: ${nonce}` 
        });
      }
    );
  } catch (error) {
    console.error('Error generating nonce:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Verify wallet and register user
app.post('/auth/verify', async (req, res) => {
  try {
    const { walletAddress, signature, nonce } = req.body;

    if (!walletAddress || !signature || !nonce) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Verify nonce exists and hasn't been used
    const nonceRecord = await new Promise((resolve, reject) => {
      db.get(
        'SELECT * FROM auth_nonces WHERE nonce = ? AND wallet_address = ? AND used = FALSE',
        [nonce, walletAddress],
        (err, row) => {
          if (err) reject(err);
          else resolve(row);
        }
      );
    });

    if (!nonceRecord) {
      return res.status(400).json({ error: 'Invalid or expired nonce' });
    }

    // Verify signature
    const message = `Sign this message to authenticate with Chatimics: ${nonce}`;
    const isValidSignature = await verifyWalletSignature(walletAddress, signature, message);
    
    if (!isValidSignature) {
      return res.status(400).json({ error: 'Invalid wallet signature' });
    }

    // Mark nonce as used
    db.run('UPDATE auth_nonces SET used = TRUE WHERE nonce = ?', [nonce]);

    // Check if user already exists
    const existingUser = await new Promise((resolve, reject) => {
      db.get(
        'SELECT * FROM nft_registrations WHERE wallet_address = ? AND is_active = TRUE',
        [walletAddress],
        (err, row) => {
          if (err) reject(err);
          else resolve(row);
        }
      );
    });

    if (existingUser) {
      // Update last verified timestamp
      db.run(
        'UPDATE nft_registrations SET last_verified = CURRENT_TIMESTAMP WHERE wallet_address = ?',
        [walletAddress]
      );

      return res.json({
        success: true,
        user: {
          matrixUserId: existingUser.matrix_user_id,
          pseudonym: existingUser.pseudonym,
          tempPassword: existingUser.temp_password,
          isNewUser: false
        }
      });
    }

    // Verify NFT ownership
    const nftVerification = await verifyNFTOwnership(walletAddress, AUTHORIZED_NFT_CREATORS);
    
    if (!nftVerification.isValid) {
      return res.status(403).json({ 
        error: 'No qualifying NFTs found. You must own an NFT from an authorized creator to register.' 
      });
    }

    // Generate user details
    const pseudonym = generatePseudonym(walletAddress);
    const matrixUserId = generateMatrixUserId(pseudonym);
    const tempPassword = generateSecurePassword();

    // Create Matrix user
    const matrixResult = await createMatrixUser(matrixUserId, tempPassword, pseudonym);
    
    if (!matrixResult.success) {
      return res.status(500).json({ error: 'Failed to create Matrix user' });
    }

    // Store registration in database
    db.run(
      `INSERT INTO nft_registrations 
       (wallet_address, matrix_user_id, pseudonym, nft_mint_address, nft_creator_address, temp_password) 
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        walletAddress,
        matrixUserId,
        pseudonym,
        nftVerification.nft.mint,
        nftVerification.nft.creator,
        tempPassword
      ],
      async function(err) {
        if (err) {
          console.error('Error storing registration:', err);
          return res.status(500).json({ error: 'Failed to store registration' });
        }

        // Invite user to main room
        await inviteUserToMainRoom(matrixUserId);

        res.json({
          success: true,
          user: {
            matrixUserId,
            pseudonym,
            tempPassword,
            nft: nftVerification.nft,
            isNewUser: true
          }
        });
      }
    );

  } catch (error) {
    console.error('Error in verify endpoint:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    authorizedCreators: AUTHORIZED_NFT_CREATORS.length
  });
});

// Admin endpoints (protected by admin token)
app.get('/admin/users', async (req, res) => {
  const adminToken = req.headers.authorization?.replace('Bearer ', '');
  
  if (adminToken !== SYNAPSE_ADMIN_TOKEN) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  db.all('SELECT wallet_address, matrix_user_id, pseudonym, nft_creator_address, registration_timestamp, last_verified, is_active FROM nft_registrations ORDER BY registration_timestamp DESC', (err, rows) => {
    if (err) {
      console.error('Error fetching users:', err);
      return res.status(500).json({ error: 'Failed to fetch users' });
    }

    res.json({ users: rows });
  });
});

// Initialize and start server
async function startServer() {
  try {
    await initDatabase();
    
    if (!HELIUS_API_KEY) {
      console.warn('Warning: HELIUS_API_KEY not set. NFT verification may not work properly.');
    }
    
    if (!SYNAPSE_ADMIN_TOKEN) {
      console.warn('Warning: SYNAPSE_ADMIN_TOKEN not set. User creation will not work.');
    }
    
    if (AUTHORIZED_NFT_CREATORS.length === 0) {
      console.warn('Warning: No AUTHORIZED_NFT_CREATORS configured.');
    }

    app.listen(PORT, () => {
      console.log(`🚀 NFT Auth Service running on port ${PORT}`);
      console.log(`📊 Monitoring ${AUTHORIZED_NFT_CREATORS.length} authorized NFT creators`);
      console.log(`🏠 Matrix server: ${MATRIX_SERVER_URL}`);
      console.log(`📁 Database: ${NFT_AUTH_DB_PATH}`);
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

startServer();
