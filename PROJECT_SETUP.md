# 🚀 Chatimics - Matrix Homeserver & Web Client Setup Guide

A comprehensive Matrix homeserver with integrated web client for decentralized chat with Web3 wallet authentication.

## 📋 Prerequisites

### macOS Setup
- **macOS** 10.15+ (Catalina or later)
- **Homebrew** package manager ([install here](https://brew.sh/))
- **Docker Desktop** for Mac
- **Domain name** with DNS access

### Required Tools (Auto-installed by setup script)
- Docker & Docker Compose
- Cloudflared (Cloudflare Tunnel)
- Basic CLI tools (curl, jq, etc.)

## 🏗️ Quick Setup

### 1. Clone and Configure
```bash
git clone <your-repo-url> chatimics
cd chatimics

# Copy environment template and configure
cp .env.example .env
# Edit .env with your actual values
```

### 2. Run Setup Script
```bash
# For macOS (recommended)
./setup_matrix_mac.sh -d chat.yourdomain.com

# For Linux systems
./setup_matrix.sh -d chat.yourdomain.com
```

The setup script will:
- ✅ Install all prerequisites via Homebrew
- ✅ Configure Cloudflare Tunnel for secure access
- ✅ Set up Matrix Synapse homeserver
- ✅ Configure and start all services
- ✅ Run connectivity tests

## 📁 Project Structure

```
chatimics/
├── 🔧 Configuration & Setup
│   ├── docker-compose.yml          # Container orchestration
│   ├── setup_matrix_mac.sh         # macOS setup script
│   ├── setup_matrix.sh             # Linux setup script
│   └── .env.example                # Environment template
│
├── 🏠 Matrix Synapse Server
│   └── synapse_server/
│       ├── data/                   # Server data (ignored in git)
│       │   ├── homeserver.yaml.template    # Config template
│       │   └── log.config.template         # Logging template
│       └── cloudflare_config/      # Tunnel configuration
│
├── 🌐 Web Client Application
│   ├── app_main/                   # Next.js web client
│   ├── app/                        # React components
│   ├── components/                 # Shared components
│   └── styles/                     # Styling
│
├── 🔐 VPN & Security (Optional)
│   ├── vpn_setup/                  # OpenVPN server setup
│   └── easy-rsa-vpn/              # PKI infrastructure
│
├── 📚 Templates & Examples
│   └── configuration_examples/     # Example configurations
│
└── 🛠️ Operational Scripts
    └── operational_scripts/        # Management utilities
```

## 🔧 Manual Configuration

### Environment Variables
Configure `.env` with your actual values:

```bash
# Required Configuration
MATRIX_SERVER_URL=https://chat.yourdomain.com
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=your-walletconnect-project-id
NEYNAR_API_KEY=your-neynar-api-key
JWT_SECRET=your-secure-jwt-secret
```

### Cloudflare Tunnel Setup
1. Create tunnel: `cloudflared tunnel create chatimics`
2. Configure DNS: Point your domain to the tunnel
3. Update `synapse_server/cloudflare_config/config.yml`

### Manual Docker Setup
```bash
# Pull and start services
docker-compose pull
docker-compose up -d

# Check service status
docker-compose ps
docker-compose logs synapse
```

## 🔄 Development Workflow

### Starting Development
```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f synapse
docker-compose logs -f webclient
```

### Making Changes
```bash
# Restart specific service after changes
docker-compose restart webclient

# Rebuild after major changes
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Database Management
```bash
# Backup database
docker-compose exec synapse sqlite3 /data/homeserver.db ".backup /data/backup.db"

# Access database
docker-compose exec synapse sqlite3 /data/homeserver.db
```

## 🔐 User Management

### Create Admin User
```bash
./register_admin.sh -u admin -p your_secure_password -d chat.yourdomain.com
```

### Bulk Register Users
```bash
./bulk_register.sh -f userlist.txt -d chat.yourdomain.com
```

## 🚨 Troubleshooting

### Common Issues

**Service won't start:**
```bash
# Check logs
docker-compose logs synapse

# Verify configuration
docker-compose config

# Reset and rebuild
docker-compose down -v
docker-compose up -d
```

**Connectivity issues:**
```bash
# Test Matrix API
curl https://chat.yourdomain.com/_matrix/client/versions

# Test federation
curl https://chat.yourdomain.com:8448/federation/v1/version

# Check DNS
dig _matrix._tcp.chat.yourdomain.com SRV
```

**Permission errors:**
```bash
# Fix data directory permissions
sudo chown -R 991:991 synapse_server/data/
```

### Log Locations
- **Synapse logs:** `synapse_server/data/*.log`
- **Docker logs:** `docker-compose logs [service]`
- **Web client logs:** Browser developer console

## 🛡️ Security Considerations

### What's Tracked in Git
- ✅ Configuration templates
- ✅ Setup scripts and documentation
- ✅ Application source code
- ✅ Example configurations

### What's NOT Tracked (Sensitive Data)
- ❌ Actual server databases and keys
- ❌ User data and media files
- ❌ Environment variables with secrets
- ❌ PKI certificates and private keys
- ❌ Cloudflare tunnel credentials

### Production Checklist
- [ ] Use strong passwords for admin accounts
- [ ] Configure rate limiting
- [ ] Set up proper SSL certificates
- [ ] Enable registration restrictions
- [ ] Regular database backups
- [ ] Monitor system resources
- [ ] Keep dependencies updated

## 📚 Additional Resources

- [Matrix Synapse Documentation](https://element-hq.github.io/synapse/latest/)
- [Cloudflare Tunnel Guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Next.js Documentation](https://nextjs.org/docs)
- [Docker Compose Reference](https://docs.docker.com/compose/)

## 🤝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

---

💡 **Need help?** Check the troubleshooting section or open an issue with detailed logs and configuration details.
