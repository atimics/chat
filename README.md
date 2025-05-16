 # Matrix Synapse Setup with Cloudflare Tunnel & AWS Route53

 This repository provides:
 - A Docker Compose configuration to run [Matrix Synapse](https://github.com/matrix-org/synapse) as a self-hosted server.
 - A Cloudflare Tunnel (`cloudflared`) config to expose the Synapse HTTP API securely without opening public ports.
 - An optional AWS Route53 automation to create DNS records (CNAME & SRV) for federation and client access.
 - A setup script (`setup_matrix.sh`) to install dependencies, configure services, and validate connectivity.

 ## Prerequisites

 - A Linux server (Debian/Ubuntu) with root or sudo privileges.
 - Docker & Docker Compose (installed by the setup script).
 - A registered domain (e.g., `chat.example.com`).
 - **Cloudflare Tunnel credentials**:
   1. Create a Tunnel in your Cloudflare dashboard (`Access` → `Tunnels`).
   2. Download the generated JSON credentials file and place it at the repo root, named exactly as `<TUNNEL_ID>.json`.
   3. Copy or update `config.yml` with your `tunnel` ID and default hostname (will be overridden by the script).
 - (Optional) **AWS Route53**:
   - If your DNS is hosted in Route53 and you want the script to configure records:
     1. Install & configure the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html).
     2. Note your Hosted Zone ID for the domain (e.g., `Z1ABCDEF...`).

 ## Files

 - `docker-compose.yml`: Runs the Synapse service, exposing ports `8008` (client API) and `8448` (federation).
 - `config.yml`: Cloudflare Tunnel ingress rules for HTTP.
 - `data/`: Synapse data directory (DB, keys, logs, media). Contains a template `homeserver.yaml`.
 - `setup_matrix.sh`: Linux install script to automate setup and validation.
 - `setup_matrix_mac.sh`: macOS install script to automate setup and validation.
 - `README.md`: This documentation.

 ## Quick Setup

 1. Make the script executable:

    ```bash
    chmod +x setup_matrix.sh
    ```

 2. Run with your domain and (optionally) Route53 zone ID (Linux only):

    ```bash
    sudo ./setup_matrix.sh \
      --domain chat.example.com \
      --zone-id Z1234567890ABCDEFG \
      --aws-region us-east-1
    ```

 - Omit `--zone-id` or add `--skip-dns` to skip Route53 changes.
 - The script will:
   1. Install Docker, Cloudflared, Certbot, AWS CLI, and dependencies.
   2. Copy and patch `docker-compose.yml`, `config.yml`, and Synapse data for your domain.
   3. Start Synapse via Docker Compose.
   4. Enable & start the `cloudflared` Tunnel as a systemd service.
   5. (Optional) Create a CNAME for your domain and an SRV record for `_matrix._tcp` in Route53.
   6. Validate HTTP, federation, and DNS records.

 After completion, your Matrix homeserver will be available at `https://chat.example.com`, and federation will work on port `8448`.
  
 ## macOS Setup

 If you're on macOS, use the provided `setup_matrix_mac.sh` script:

 1. Ensure Homebrew is installed: https://brew.sh
 2. Make the script executable:
    ```bash
    chmod +x setup_matrix_mac.sh
    ```
 3. From the repository root (where `setup_matrix_mac.sh` and `config.yml` reside), run the script:
    ```bash
    ./setup_matrix_mac.sh --domain chat.example.com --skip-dns
    ```
    Do **not** run it from `~/.cloudflared` or another directory, to ensure it finds the correct repository files.
 4. Configure your DNS records manually as described above.

 ## Manual DNS Configuration

 If you prefer manual changes, create the following records in your DNS provider:

 1. **CNAME**
    - Name: `chat` (or your subdomain)
    - Target: `<TUNNEL_ID>.cfargotunnel.com`
    - TTL: `300`
 2. **SRV**
    - Service: `_matrix._tcp`
    - Protocol: `_tcp`
    - Name: `chat.example.com`
    - Priority: `0`, Weight: `0`, Port: `8448`, Target: `chat.example.com`
    - TTL: `300`

 Ensure any existing A or CNAME records do not conflict. For federation, the SRV record directs federating servers to connect over port `8448`.

 ## Troubleshooting & Logs

 - Synapse logs: `docker-compose -f /opt/matrix-synapse/docker-compose.yml logs -f matrix`
 - Cloudflared logs: `journalctl -u cloudflared -f`
 - Check DNS records: `dig +short SRV _matrix._tcp.chat.example.com`
 - Test client API: `curl -I https://chat.example.com/_matrix/client/versions`
 - Test federation API: `curl -I https://chat.example.com:8448/federation/v1/version`

 ## Next Steps

 - Register an admin user:

   ```bash
   docker exec -it matrix-synapse register_new_matrix_user -c /data/homeserver.yaml https://localhost:8008
   ```

 - Secure media storage, integrate with backups, or add reverse proxies (e.g., Nginx/Caddy) if you prefer self-hosted TLS.
 - Monitor usage and scale with Kubernetes or multiple worker nodes as needed.

 ---

 Feel free to contribute improvements or file issues! Happy chatting :)