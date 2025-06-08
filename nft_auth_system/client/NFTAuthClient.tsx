'use client';

import React, { useState, useEffect, useRef } from 'react';
import { useWallet } from '@solana/wallet-adapter-react';
import { WalletMultiButton } from '@solana/wallet-adapter-react-ui';
import { sign } from 'tweetnacl';
import bs58 from 'bs58';

interface NFTAuthClientProps {
  onAuthenticated: (credentials: any) => void;
}

interface Message {
  id: string;
  sender: string;
  content: string;
  timestamp: number;
  type: 'text' | 'image' | 'file';
  senderPseudonym?: string;
}

interface AuthCredentials {
  matrixUserId: string;
  pseudonym: string;
  tempPassword: string;
  accessToken?: string;
}

interface NFTInfo {
  mint: string;
  creator: string;
  name: string;
  image?: string;
}

const NFT_AUTH_API_URL = process.env.NEXT_PUBLIC_NFT_AUTH_API_URL || 'http://localhost:3002';
const MATRIX_SERVER_URL = process.env.NEXT_PUBLIC_MATRIX_SERVER_URL || 'https://chat.ratimics.com';

export default function NFTAuthClient() {
  const { publicKey, signMessage, connected } = useWallet();
  
  // Authentication state
  const [authState, setAuthState] = useState<'disconnected' | 'signing' | 'authenticated'>('disconnected');
  const [credentials, setCredentials] = useState<AuthCredentials | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [nftInfo, setNftInfo] = useState<NFTInfo | null>(null);
  
  // Chat state
  const [messages, setMessages] = useState<Message[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [matrixClient, setMatrixClient] = useState<any>(null);
  const [roomId] = useState('!main:chat.ratimics.com'); // Single room
  const [isLoadingMessages, setIsLoadingMessages] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (connected && publicKey && authState === 'disconnected') {
      handleWalletAuth();
    }
  }, [connected, publicKey]);

  useEffect(() => {
    if (credentials && authState === 'authenticated') {
      initializeMatrixClient();
    }
  }, [credentials, authState]);

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  const handleWalletAuth = async () => {
    if (!publicKey || !signMessage) {
      setError('Wallet not properly connected');
      return;
    }

    setAuthState('signing');
    setError(null);

    try {
      // Step 1: Get nonce from auth service
      const nonceResponse = await fetch(`${NFT_AUTH_API_URL}/auth/nonce`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          walletAddress: publicKey.toString(),
        }),
      });

      if (!nonceResponse.ok) {
        const errorData = await nonceResponse.json();
        throw new Error(errorData.error || 'Failed to get authentication nonce');
      }

      const { nonce, message } = await nonceResponse.json();

      // Step 2: Sign the message
      const messageBytes = new TextEncoder().encode(message);
      const signature = await signMessage(messageBytes);
      const signatureBase58 = bs58.encode(signature);

      // Step 3: Verify signature and register/authenticate
      const verifyResponse = await fetch(`${NFT_AUTH_API_URL}/auth/verify`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          walletAddress: publicKey.toString(),
          signature: signatureBase58,
          nonce,
        }),
      });

      if (!verifyResponse.ok) {
        const errorData = await verifyResponse.json();
        throw new Error(errorData.error || 'Authentication failed');
      }

      const { user, success } = await verifyResponse.json();

      if (success) {
        const creds: AuthCredentials = {
          matrixUserId: user.matrixUserId,
          pseudonym: user.pseudonym,
          tempPassword: user.tempPassword,
        };

        setCredentials(creds);
        if (user.nft) {
          setNftInfo(user.nft);
        }
        setAuthState('authenticated');
      }

    } catch (error: any) {
      console.error('Authentication error:', error);
      setError(error.message || 'Authentication failed');
      setAuthState('disconnected');
    }
  };

  const initializeMatrixClient = async () => {
    if (!credentials) return;

    try {
      setIsLoadingMessages(true);

      // Login to Matrix server
      const loginResponse = await fetch(`${MATRIX_SERVER_URL}/_matrix/client/r0/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          type: 'm.login.password',
          user: credentials.matrixUserId,
          password: credentials.tempPassword,
        }),
      });

      if (!loginResponse.ok) {
        throw new Error('Failed to login to Matrix server');
      }

      const loginData = await loginResponse.json();
      setCredentials(prev => prev ? { ...prev, accessToken: loginData.access_token } : null);

      // Initialize matrix client (simplified)
      setMatrixClient({
        accessToken: loginData.access_token,
        userId: credentials.matrixUserId,
        deviceId: loginData.device_id,
      });

      // Load initial messages
      await loadMessages(loginData.access_token);

      // Set up polling for new messages
      startMessagePolling(loginData.access_token);

    } catch (error) {
      console.error('Failed to initialize Matrix client:', error);
      setError('Failed to connect to chat server');
    } finally {
      setIsLoadingMessages(false);
    }
  };

  const loadMessages = async (accessToken: string) => {
    try {
      const response = await fetch(
        `${MATRIX_SERVER_URL}/_matrix/client/r0/rooms/${encodeURIComponent(roomId)}/messages?limit=50&dir=b`,
        {
          headers: {
            'Authorization': `Bearer ${accessToken}`,
          },
        }
      );

      if (response.ok) {
        const data = await response.json();
        const formattedMessages: Message[] = data.chunk
          .filter((event: any) => event.type === 'm.room.message')
          .reverse()
          .map((event: any) => ({
            id: event.event_id,
            sender: event.sender,
            content: event.content.body || '',
            timestamp: event.origin_server_ts,
            type: 'text',
            senderPseudonym: extractPseudonymFromUserId(event.sender),
          }));

        setMessages(formattedMessages);
      }
    } catch (error) {
      console.error('Failed to load messages:', error);
    }
  };

  const extractPseudonymFromUserId = (userId: string): string => {
    // Extract pseudonym from Matrix user ID (@pseudonym:domain.com)
    const match = userId.match(/@([^:]+):/);
    return match ? match[1].replace(/_/g, ' ') : userId;
  };

  const startMessagePolling = (accessToken: string) => {
    const pollInterval = setInterval(async () => {
      if (messages.length > 0) {
        const lastMessage = messages[messages.length - 1];
        try {
          const response = await fetch(
            `${MATRIX_SERVER_URL}/_matrix/client/r0/rooms/${encodeURIComponent(roomId)}/messages?from=${lastMessage.id}&dir=f&limit=10`,
            {
              headers: {
                'Authorization': `Bearer ${accessToken}`,
              },
            }
          );

          if (response.ok) {
            const data = await response.json();
            const newMessages: Message[] = data.chunk
              .filter((event: any) => event.type === 'm.room.message')
              .map((event: any) => ({
                id: event.event_id,
                sender: event.sender,
                content: event.content.body || '',
                timestamp: event.origin_server_ts,
                type: 'text',
                senderPseudonym: extractPseudonymFromUserId(event.sender),
              }));

            if (newMessages.length > 0) {
              setMessages(prev => [...prev, ...newMessages]);
            }
          }
        } catch (error) {
          console.error('Error polling for messages:', error);
        }
      }
    }, 2000); // Poll every 2 seconds

    return () => clearInterval(pollInterval);
  };

  const sendMessage = async () => {
    if (!newMessage.trim() || !matrixClient) return;

    try {
      const response = await fetch(
        `${MATRIX_SERVER_URL}/_matrix/client/r0/rooms/${encodeURIComponent(roomId)}/send/m.room.message`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${matrixClient.accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            msgtype: 'm.text',
            body: newMessage,
          }),
        }
      );

      if (response.ok) {
        setNewMessage('');
        // Message will appear via polling
      } else {
        throw new Error('Failed to send message');
      }
    } catch (error) {
      console.error('Failed to send message:', error);
      setError('Failed to send message');
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  const handleLogout = () => {
    setAuthState('disconnected');
    setCredentials(null);
    setMessages([]);
    setMatrixClient(null);
    setError(null);
    setNftInfo(null);
  };

  // Render authentication screen
  if (authState !== 'authenticated') {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 flex items-center justify-center p-4">
        <div className="bg-black/20 backdrop-blur-lg rounded-2xl p-8 max-w-md w-full border border-white/10">
          <div className="text-center mb-8">
            <h1 className="text-3xl font-bold text-white mb-2">Chatimics</h1>
            <p className="text-purple-200">NFT-Gated Community Chat</p>
          </div>

          {error && (
            <div className="bg-red-500/20 border border-red-500/50 rounded-lg p-4 mb-6">
              <p className="text-red-200 text-sm">{error}</p>
            </div>
          )}

          <div className="space-y-6">
            <div className="text-center">
              <WalletMultiButton className="!bg-gradient-to-r !from-purple-600 !to-blue-600 hover:!from-purple-700 hover:!to-blue-700 !rounded-lg !font-medium !transition-all !duration-200" />
            </div>

            {authState === 'signing' && (
              <div className="text-center">
                <div className="animate-spin h-6 w-6 border-2 border-purple-500 border-t-transparent rounded-full mx-auto mb-2"></div>
                <p className="text-purple-200 text-sm">Verifying NFT ownership...</p>
              </div>
            )}

            <div className="text-xs text-gray-400 text-center">
              <p>Connect your Solana wallet to verify NFT ownership</p>
              <p className="mt-1">Only holders of authorized NFTs can access this chat</p>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Render chat interface
  return (
    <div className="min-h-screen bg-gray-900 flex flex-col">
      {/* Header */}
      <div className="bg-gray-800 border-b border-gray-700 p-4">
        <div className="flex items-center justify-between max-w-6xl mx-auto">
          <div className="flex items-center space-x-4">
            <h1 className="text-xl font-bold text-white">Chatimics</h1>
            <div className="text-sm text-gray-400">
              Welcome, <span className="text-purple-400">{credentials?.pseudonym}</span>
            </div>
          </div>
          
          <div className="flex items-center space-x-4">
            {nftInfo && (
              <div className="text-xs text-gray-400">
                <span className="text-green-400">✓</span> NFT Verified
              </div>
            )}
            <button
              onClick={handleLogout}
              className="text-gray-400 hover:text-white text-sm"
            >
              Logout
            </button>
          </div>
        </div>
      </div>

      {/* Main Chat Area */}
      <div className="flex-1 flex flex-col max-w-6xl mx-auto w-full">
        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4">
          {isLoadingMessages ? (
            <div className="flex items-center justify-center h-32">
              <div className="animate-spin h-6 w-6 border-2 border-purple-500 border-t-transparent rounded-full"></div>
            </div>
          ) : (
            <div className="space-y-4">
              {messages.map((message) => (
                <div
                  key={message.id}
                  className={`flex ${message.sender === credentials?.matrixUserId ? 'justify-end' : 'justify-start'}`}
                >
                  <div
                    className={`max-w-xs lg:max-w-md px-4 py-2 rounded-lg ${
                      message.sender === credentials?.matrixUserId
                        ? 'bg-purple-600 text-white'
                        : 'bg-gray-700 text-gray-200'
                    }`}
                  >
                    {message.sender !== credentials?.matrixUserId && (
                      <div className="text-xs text-gray-400 mb-1">
                        {message.senderPseudonym}
                      </div>
                    )}
                    <p className="text-sm">{message.content}</p>
                    <div className="text-xs opacity-70 mt-1">
                      {new Date(message.timestamp).toLocaleTimeString()}
                    </div>
                  </div>
                </div>
              ))}
              <div ref={messagesEndRef} />
            </div>
          )}
        </div>

        {/* Message Input */}
        <div className="p-4 border-t border-gray-700">
          <div className="flex space-x-2">
            <input
              type="text"
              value={newMessage}
              onChange={(e) => setNewMessage(e.target.value)}
              onKeyPress={handleKeyPress}
              placeholder="Type your message..."
              className="flex-1 bg-gray-800 border border-gray-600 rounded-lg px-4 py-2 text-white placeholder-gray-400 focus:outline-none focus:border-purple-500"
            />
            <button
              onClick={sendMessage}
              disabled={!newMessage.trim()}
              className="bg-purple-600 hover:bg-purple-700 disabled:bg-gray-600 disabled:cursor-not-allowed text-white px-6 py-2 rounded-lg font-medium transition-colors"
            >
              Send
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
