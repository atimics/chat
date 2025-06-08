#!/bin/bash

# Chatimics Matrix Web Client Setup Script

echo "🚀 Setting up Chatimics Matrix Web Client..."

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js first."
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed. Please install npm first."
    exit 1
fi

echo "📦 Installing dependencies..."
npm install

# Create a simple .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "📝 Creating .env file..."
    cat > .env << EOL
PORT=3000
MATRIX_SERVER_URL=https://chat.ratimics.com
NODE_ENV=development
EOL
fi

echo "✅ Setup complete!"
echo ""
echo "🌟 To start the web client:"
echo "   npm start"
echo ""
echo "🌐 The web client will be available at:"
echo "   http://localhost:3000"
echo ""
echo "💡 Make sure your Matrix server is running and accessible at:"
echo "   https://chat.ratimics.com"
echo ""
echo "🔐 Users will need to connect their crypto wallet and sign a message"
echo "   to authenticate and access the Matrix chat."
