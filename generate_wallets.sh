#!/bin/bash

# Wallet Address Generator for Chatimics Users
# This script generates wallet addresses from usernames in userlist.txt

echo "🔐 Generating wallet addresses for approved users..."

if [ ! -f "userlist.txt" ]; then
    echo "❌ userlist.txt not found!"
    exit 1
fi

# Create wallet mapping file
echo "# Wallet Address Mapping for Chatimics Users" > wallet_mapping.txt
echo "# Format: username wallet_address password/token" >> wallet_mapping.txt
echo "" >> wallet_mapping.txt

while IFS= read -r line; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^# ]]; then
        continue
    fi
    
    # Parse username and token
    username=$(echo "$line" | awk '{print $1}')
    token=$(echo "$line" | awk '{print $2}')
    
    if [ -n "$username" ] && [ -n "$token" ]; then
        # Generate a deterministic "wallet address" from username
        # In production, these would be real wallet addresses provided by users
        hash=$(echo -n "$username" | sha256sum | cut -c1-40)
        wallet_address="0x$hash"
        
        echo "$username $wallet_address $token" >> wallet_mapping.txt
        echo "✅ Generated wallet for $username: $wallet_address"
    fi
done < userlist.txt

echo ""
echo "📝 Wallet mapping saved to wallet_mapping.txt"
echo "💡 In production, replace these generated addresses with real wallet addresses"

# Also create a JSON version for the web client
echo "Creating JSON version for web client..."

cat > approved_wallets.json << 'EOL'
{
  "wallets": [
EOL

first=true
while IFS= read -r line; do
    if [[ -z "$line" || "$line" =~ ^# ]]; then
        continue
    fi
    
    username=$(echo "$line" | awk '{print $1}')
    if [ -n "$username" ]; then
        hash=$(echo -n "$username" | sha256sum | cut -c1-40)
        wallet_address="0x$hash"
        
        if [ "$first" = true ]; then
            echo "    \"$wallet_address\"" >> approved_wallets.json
            first=false
        else
            echo "    ,\"$wallet_address\"" >> approved_wallets.json
        fi
    fi
done < userlist.txt

cat >> approved_wallets.json << 'EOL'
  ]
}
EOL

echo "✅ JSON wallet list saved to approved_wallets.json"
