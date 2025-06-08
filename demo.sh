#!/bin/bash

# Demo script for Chatimics Matrix Web Client
echo "🚀 Chatimics Matrix Web Client Demo"
echo "====================================="
echo ""

echo "📊 System Status:"
echo "• API Server: http://localhost:3001"
echo "• Web Client: http://localhost:3002"
echo "• Matrix Server: https://chat.ratimics.com"
echo ""

echo "🔍 Testing API endpoints..."

echo ""
echo "📋 Health Check:"
curl -s http://localhost:3001/health | jq .

echo ""
echo "💼 Approved Wallets (first 3):"
curl -s http://localhost:3001/api/approved-wallets | jq '.wallets[:3]'

echo ""
echo "🟣 Farcaster Users (first 3):"
curl -s http://localhost:3001/api/approved-farcaster-users | jq '.users[:3]'

echo ""
echo "📈 User Statistics:"
curl -s http://localhost:3001/api/stats | jq .

echo ""
echo "🌟 Features Available:"
echo "• 🔐 Multi-wallet authentication (100+ wallets via RainbowKit)"
echo "• 🟣 Farcaster social authentication"
echo "• 💬 Real-time Matrix chat"
echo "• 🎨 Modern glassmorphism UI"
echo "• 📱 Mobile responsive design"
echo "• 🔒 Cryptographic signature verification"
echo ""

echo "🔗 Quick Links:"
echo "• Web Client: http://localhost:3002"
echo "• API Health: http://localhost:3001/health"
echo "• Wallet List: http://localhost:3001/api/approved-wallets"
echo "• Farcaster Users: http://localhost:3001/api/approved-farcaster-users"
echo ""

echo "💡 Next Steps:"
echo "1. Open http://localhost:3002 in your browser"
echo "2. Connect your wallet (MetaMask, WalletConnect, etc.)"
echo "3. Sign the authentication message"
echo "4. Start chatting on Matrix!"
echo ""
echo "🟣 Or sign in with Farcaster for instant access!"
