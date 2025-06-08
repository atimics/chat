'use client';

import React, { useState, useEffect, useRef } from 'react';

interface MatrixClientProps {
  credentials: any;
  authMethod: 'wallet' | 'farcaster';
  onLogout: () => void;
}

interface Message {
  id: string;
  sender: string;
  content: string;
  timestamp: number;
  type: 'text' | 'image' | 'file';
}

interface Room {
  id: string;
  name: string;
  memberCount: number;
  lastMessage?: Message;
}

export default function MatrixClient({ credentials, authMethod, onLogout }: MatrixClientProps) {
  const [rooms, setRooms] = useState<Room[]>([]);
  const [currentRoom, setCurrentRoom] = useState<Room | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [loading, setLoading] = useState(true);
  const [connected, setConnected] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    initializeMatrixClient();
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  const initializeMatrixClient = async () => {
    try {
      // Initialize Matrix client (simplified for demo)
      // In production, you'd use the matrix-js-sdk
      
      // Simulate loading
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Mock data for demonstration
      const mockRooms: Room[] = [
        { 
          id: '!general:chat.ratimics.com', 
          name: 'General Chat', 
          memberCount: 12,
          lastMessage: {
            id: '1',
            sender: '@alice:chat.ratimics.com',
            content: 'Welcome to the general chat!',
            timestamp: Date.now() - 3600000,
            type: 'text'
          }
        },
        { 
          id: '!crypto:chat.ratimics.com', 
          name: 'Crypto Discussion', 
          memberCount: 8,
          lastMessage: {
            id: '2',
            sender: '@bob:chat.ratimics.com',
            content: 'What do you think about the latest DeFi trends?',
            timestamp: Date.now() - 1800000,
            type: 'text'
          }
        },
        { 
          id: '!farcaster:chat.ratimics.com', 
          name: 'Farcaster Community', 
          memberCount: 15,
          lastMessage: {
            id: '3',
            sender: '@charlie:chat.ratimics.com',
            content: 'Great to see more Farcaster users joining!',
            timestamp: Date.now() - 900000,
            type: 'text'
          }
        }
      ];

      setRooms(mockRooms);
      setCurrentRoom(mockRooms[0]);
      setConnected(true);
      setLoading(false);
      
      // Load messages for the first room
      loadRoomMessages(mockRooms[0].id);
      
    } catch (error) {
      console.error('Failed to initialize Matrix client:', error);
      setLoading(false);
    }
  };

  const loadRoomMessages = async (roomId: string) => {
    // Mock messages for demonstration
    const mockMessages: Message[] = [
      {
        id: '1',
        sender: '@alice:chat.ratimics.com',
        content: 'Welcome to the general chat!',
        timestamp: Date.now() - 3600000,
        type: 'text'
      },
      {
        id: '2',
        sender: '@system:chat.ratimics.com',
        content: `${credentials.matrixUsername} has joined the room`,
        timestamp: Date.now() - 1800000,
        type: 'text'
      },
      {
        id: '3',
        sender: '@bob:chat.ratimics.com',
        content: 'Hey everyone! How is everyone doing today?',
        timestamp: Date.now() - 900000,
        type: 'text'
      }
    ];

    setMessages(mockMessages);
  };

  const sendMessage = async () => {
    if (!newMessage.trim() || !currentRoom) return;

    const message: Message = {
      id: Date.now().toString(),
      sender: credentials.matrixUsername,
      content: newMessage,
      timestamp: Date.now(),
      type: 'text'
    };

    // Add message to UI immediately
    setMessages(prev => [...prev, message]);
    setNewMessage('');

    try {
      // In production, send to Matrix server
      await fetch('/api/send-message', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          roomId: currentRoom.id,
          message: newMessage,
          credentials
        })
      });
    } catch (error) {
      console.error('Failed to send message:', error);
    }
  };

  const selectRoom = (room: Room) => {
    setCurrentRoom(room);
    loadRoomMessages(room.id);
  };

  const formatTime = (timestamp: number) => {
    return new Date(timestamp).toLocaleTimeString([], { 
      hour: '2-digit', 
      minute: '2-digit' 
    });
  };

  const getAvatarColor = (sender: string) => {
    const colors = [
      'bg-red-500', 'bg-blue-500', 'bg-green-500', 'bg-yellow-500',
      'bg-purple-500', 'bg-pink-500', 'bg-indigo-500', 'bg-teal-500'
    ];
    const index = sender.charCodeAt(1) % colors.length;
    return colors[index];
  };

  if (loading) {
    return (
      <div className="gradient-bg min-h-screen flex items-center justify-center">
        <div className="glass-effect rounded-2xl p-8 text-center">
          <i className="fas fa-spinner fa-spin text-4xl text-white mb-4"></i>
          <h2 className="text-2xl font-bold text-white mb-2">
            Connecting to Matrix...
          </h2>
          <p className="text-gray-300">
            Setting up your secure chat session
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="gradient-bg min-h-screen">
      <div className="container mx-auto px-4 py-4">
        {/* Header */}
        <header className="glass-effect rounded-xl p-4 mb-4">
          <div className="flex justify-between items-center">
            <div className="flex items-center space-x-4">
              <h1 className="text-2xl font-bold text-white">
                <i className="fas fa-comments mr-2"></i>Chatimics
              </h1>
              {connected && (
                <div className="flex items-center space-x-2">
                  <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
                  <span className="text-green-400 text-sm">Connected</span>
                </div>
              )}
            </div>
            
            <div className="flex items-center space-x-4">
              <div className="text-right">
                <p className="text-white font-medium">
                  {authMethod === 'farcaster' ? '🟣' : '👛'} {credentials.matrixUsername}
                </p>
                <p className="text-gray-400 text-xs">
                  {authMethod === 'farcaster' ? 'Farcaster' : 'Wallet'} Auth
                </p>
              </div>
              <button
                onClick={onLogout}
                className="bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded-lg transition-colors"
              >
                <i className="fas fa-sign-out-alt mr-2"></i>Logout
              </button>
            </div>
          </div>
        </header>

        {/* Main Chat Interface */}
        <div className="grid grid-cols-1 lg:grid-cols-4 gap-4 h-[calc(100vh-120px)]">
          {/* Room List */}
          <div className="lg:col-span-1">
            <div className="glass-effect rounded-xl p-4 h-full">
              <h3 className="text-lg font-semibold text-white mb-4 flex items-center">
                <i className="fas fa-list mr-2"></i>Rooms
              </h3>
              <div className="space-y-2 overflow-y-auto">
                {rooms.map(room => (
                  <div
                    key={room.id}
                    onClick={() => selectRoom(room)}
                    className={`p-3 rounded-lg cursor-pointer transition-all ${
                      currentRoom?.id === room.id 
                        ? 'bg-blue-600 bg-opacity-50' 
                        : 'bg-white bg-opacity-10 hover:bg-opacity-20'
                    }`}
                  >
                    <div className="flex justify-between items-start mb-1">
                      <h4 className="text-white font-medium text-sm">{room.name}</h4>
                      <span className="text-xs text-gray-400">{room.memberCount}</span>
                    </div>
                    {room.lastMessage && (
                      <p className="text-gray-300 text-xs truncate">
                        {room.lastMessage.content}
                      </p>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Chat Area */}
          <div className="lg:col-span-3">
            <div className="glass-effect rounded-xl p-4 h-full flex flex-col">
              {/* Chat Header */}
              {currentRoom && (
                <div className="border-b border-gray-600 pb-3 mb-4">
                  <h3 className="text-xl font-semibold text-white">
                    {currentRoom.name}
                  </h3>
                  <p className="text-gray-400 text-sm">
                    {currentRoom.memberCount} members
                  </p>
                </div>
              )}

              {/* Messages */}
              <div className="flex-1 overflow-y-auto mb-4 space-y-4">
                {messages.map(message => (
                  <div key={message.id} className="flex items-start space-x-3">
                    <div className={`w-8 h-8 rounded-full flex items-center justify-center text-white text-sm font-bold ${getAvatarColor(message.sender)}`}>
                      {message.sender.charAt(1).toUpperCase()}
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center space-x-2 mb-1">
                        <span className="text-white font-medium text-sm">
                          {message.sender}
                        </span>
                        <span className="text-gray-400 text-xs">
                          {formatTime(message.timestamp)}
                        </span>
                      </div>
                      <div className="text-gray-200 text-sm">
                        {message.content}
                      </div>
                    </div>
                  </div>
                ))}
                <div ref={messagesEndRef} />
              </div>

              {/* Message Input */}
              <div className="flex space-x-2">
                <input
                  type="text"
                  value={newMessage}
                  onChange={(e) => setNewMessage(e.target.value)}
                  onKeyPress={(e) => e.key === 'Enter' && sendMessage()}
                  placeholder="Type your message..."
                  className="flex-1 bg-white bg-opacity-10 border border-gray-600 rounded-lg px-4 py-2 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <button
                  onClick={sendMessage}
                  disabled={!newMessage.trim()}
                  className="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 text-white px-6 py-2 rounded-lg transition-colors"
                >
                  <i className="fas fa-paper-plane"></i>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
