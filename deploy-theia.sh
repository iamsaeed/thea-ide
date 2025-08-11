#!/bin/bash

# Theia IDE Deployment Script for Ubuntu Server
# This script installs and configures Theia IDE with Docker, Nginx, SSL, and auto-restart capabilities

set -e  # Exit on error

# Configuration
DOMAIN="ide.codewithus.com"
EMAIL="admin@codewithus.com"  # Change this to your email for Let's Encrypt
THEIA_WORKSPACE="/home/theia-workspace"
THEIA_USER="theia"
THEIA_UID=1001
THEIA_GID=1001
GITHUB_REPO="https://github.com/iamsaeed/thea-ide"
PROJECT_DIR="/opt/theia-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

log_info "Starting Theia IDE deployment for domain: $DOMAIN"

# Update system
log_info "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
log_info "Installing required packages..."
apt-get install -y \
    curl \
    wget \
    git \
    ufw \
    fail2ban \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# Install Docker
if ! command -v docker &> /dev/null; then
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # Add current user to docker group
    usermod -aG docker $SUDO_USER 2>/dev/null || true
else
    log_info "Docker is already installed"
fi

# Install Docker Compose
if ! command -v docker-compose &> /dev/null; then
    log_info "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    log_info "Docker Compose is already installed"
fi

# Install Nginx
log_info "Installing Nginx..."
apt-get install -y nginx

# Install Certbot for SSL
log_info "Installing Certbot for SSL certificates..."
apt-get install -y certbot python3-certbot-nginx

# Create persistent workspace directory
log_info "Creating persistent workspace directory..."
mkdir -p $THEIA_WORKSPACE
mkdir -p $THEIA_WORKSPACE/.theia
mkdir -p $THEIA_WORKSPACE/projects

# Create theia user if not exists
if ! id -u $THEIA_USER > /dev/null 2>&1; then
    log_info "Creating theia user..."
    groupadd -g $THEIA_GID $THEIA_USER
    useradd -m -u $THEIA_UID -g $THEIA_GID -s /bin/bash $THEIA_USER
fi

# Set proper permissions
chown -R $THEIA_UID:$THEIA_GID $THEIA_WORKSPACE
chmod -R 755 $THEIA_WORKSPACE

# Clone or pull the Theia IDE repository
log_info "Setting up Theia IDE from GitHub repository..."
if [ -d "$PROJECT_DIR" ]; then
    log_info "Project directory exists, pulling latest changes..."
    cd "$PROJECT_DIR"
    git pull origin main || git pull origin master
else
    log_info "Cloning Theia IDE repository..."
    git clone "$GITHUB_REPO" "$PROJECT_DIR"
    cd "$PROJECT_DIR"
fi

# Check if project files exist
if [ ! -f "package.json" ]; then
    log_error "package.json not found in the repository"
    exit 1
fi

# Create .env file from .env.production if it doesn't exist
if [ ! -f ".env" ]; then
    log_info "Creating .env file..."
    cat > .env << 'EOF'
# Production Environment Variables for Theia IDE

# Node environment
NODE_ENV=production

# Theia Configuration
THEIA_WEBVIEW_EXTERNAL_ENDPOINT={{hostname}}
THEIA_MINI_BROWSER_HOST_PATTERN={{hostname}}

# Security
THEIA_ENFORCE_SSL=true
THEIA_DISABLE_STRICT_SSL=false

# Performance
THEIA_FILE_UPLOAD_SIZE_LIMIT=104857600
THEIA_WORKSPACE_DELETE_FILE_CONFIRM=true

# Logging
THEIA_LOG_LEVEL=info

# Extensions
THEIA_PLUGINS_DIR=/home/theia/.theia/plugins
THEIA_FRONTEND_DECORATIONS_COLOR=true

# Terminal
THEIA_TERMINAL_ENABLE_COPY_ON_SELECTION=true
THEIA_SHELL=/bin/bash

# File Watching
THEIA_FILE_WATCHER_VERBOSE=false

# Memory limits (in MB)
NODE_OPTIONS=--max-old-space-size=2048
EOF
    log_info ".env file created"
fi

# Update docker-compose.yml with persistent volumes
log_info "Updating docker-compose.yml with persistent volumes..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  theia-ide:
    build: .
    container_name: theia-ide
    ports:
      - "127.0.0.1:3000:3000"
    restart: always
    environment:
      - NODE_ENV=production
      - THEIA_WEBVIEW_EXTERNAL_ENDPOINT={{hostname}}
    volumes:
      # Mount the persistent workspace as the default workspace
      - /home/theia-workspace:/home/theia:rw
      # Mount Theia settings for persistence
      - /home/theia-workspace/.theia:/home/theia/.theia:rw
    user: "1001:1001"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - theia-network

networks:
  theia-network:
    driver: bridge
EOF

# Update Dockerfile to set correct working directory
log_info "Updating Dockerfile for persistent workspace..."
cat > Dockerfile << 'EOF'
# Use Node.js 20 LTS as base image
FROM node:20-alpine

# Set working directory for build
WORKDIR /app

# Install system dependencies needed for native modules
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    openssh-client

# Ensure we have the correct yarn version (1.x, not 2.x)
# Node alpine images come with yarn pre-installed, but we need to ensure it's 1.x
RUN yarn --version && \
    if [ "$(yarn --version | cut -d. -f1)" -ge "2" ]; then \
        npm uninstall -g yarn && npm install -g yarn@1.22.19; \
    fi

# Copy package files first for better Docker layer caching
COPY package*.json ./
COPY yarn.lock* ./

# Install dependencies
RUN yarn install --frozen-lockfile --network-timeout 100000

# Copy the rest of the application code
COPY . .

# Build the application
RUN yarn rebuild && yarn run bundle

# Create a non-root user for security (matching our host theia user)
RUN addgroup -g 1001 -S theia && \
    adduser -S theia -u 1001 -G theia

# Create home directory structure
RUN mkdir -p /home/theia/.theia && \
    chown -R theia:theia /home/theia

# Change ownership of the app directory to theia user
RUN chown -R theia:theia /app

# Switch to non-root user
USER theia

# Set the working directory to the mounted workspace
WORKDIR /home/theia

# Expose the default Theia port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000 || exit 1

# Start the application from the app directory but with workspace as cwd
CMD cd /app && yarn start --hostname=0.0.0.0 --port=3000 /home/theia
EOF

# Create initial HTTP-only Nginx configuration (before SSL)
log_info "Creating Nginx configuration..."
cat > /etc/nginx/sites-available/theia-ide << EOF
# Rate limiting zone (must be defined outside server blocks)
limit_req_zone \$binary_remote_addr zone=theia_limit:10m rate=10r/s;

# HTTP Server (will be updated to include HTTPS after SSL cert is obtained)
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Apply rate limiting
    limit_req zone=theia_limit burst=20 nodelay;
    
    # Proxy settings
    client_max_body_size 100M;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
    
    # Main location
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        
        # Headers for proxying
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support (required for terminal)
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Buffering settings
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    # WebSocket specific location
    location ~* \.(ws|wss) {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }
}
EOF

# Enable Nginx site
ln -sf /etc/nginx/sites-available/theia-ide /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

# Create systemd service for Docker Compose
log_info "Creating systemd service for auto-restart..."
cat > /etc/systemd/system/theia-ide.service << EOF
[Unit]
Description=Theia IDE Docker Container
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
WorkingDirectory=$PROJECT_DIR
ExecStartPre=/usr/local/bin/docker-compose down
ExecStart=/usr/local/bin/docker-compose up
ExecStop=/usr/local/bin/docker-compose down
StandardOutput=journal
StandardError=journal
SyslogIdentifier=theia-ide

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Restart policy
StartLimitInterval=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

# Configure UFW firewall
log_info "Configuring firewall..."
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw reload

# Configure fail2ban for Nginx
log_info "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
action = iptables-multiport[name=ReqLimit, port="http,https", protocol=tcp]
logpath = /var/log/nginx/error.log
findtime = 600
maxretry = 10
bantime = 7200

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 2
EOF

# Restart fail2ban
systemctl restart fail2ban

# Build and start Docker container
log_info "Building Docker image..."
docker-compose build

log_info "Starting Theia IDE container..."
docker-compose up -d

# Wait for container to be healthy
log_info "Waiting for Theia IDE to be ready..."
for i in {1..30}; do
    if docker-compose ps | grep -q "healthy"; then
        log_info "Theia IDE is healthy"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable theia-ide.service

# Restart Nginx
systemctl restart nginx

# Obtain SSL certificate
log_info "Obtaining SSL certificate for $DOMAIN..."
log_warning "Make sure your domain $DOMAIN is pointing to this server's IP address"
read -p "Press Enter when your DNS is configured correctly..."

# Get SSL certificate first (using webroot method for initial cert)
certbot certonly --webroot -w /var/www/html -d $DOMAIN --non-interactive --agree-tos --email $EMAIL

# Now update Nginx configuration with SSL
log_info "Updating Nginx configuration with SSL..."
cat > /etc/nginx/sites-available/theia-ide << EOF
# Rate limiting zone (must be defined outside server blocks)
limit_req_zone \$binary_remote_addr zone=theia_limit:10m rate=10r/s;

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS Server
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $DOMAIN;
    
    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Apply rate limiting
    limit_req zone=theia_limit burst=20 nodelay;
    
    # Proxy settings
    client_max_body_size 100M;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
    
    # Main location
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        
        # Headers for proxying
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support (required for terminal)
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Buffering settings
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    # WebSocket specific location
    location ~* \.(ws|wss) {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }
}
EOF

# Reload Nginx with new configuration
nginx -t && systemctl reload nginx

# Final setup
log_info "Creating convenience scripts..."

# Create update script
cat > /usr/local/bin/update-theia << 'EOF'
#!/bin/bash
cd /opt/theia-app
echo "Stopping Theia IDE..."
docker-compose down
echo "Pulling latest changes from GitHub..."
git pull origin main || git pull origin master
echo "Rebuilding Docker image..."
docker-compose build --no-cache
echo "Starting Theia IDE..."
docker-compose up -d
echo "Theia IDE has been updated successfully"
echo "Checking container status..."
sleep 5
docker-compose ps
EOF
chmod +x /usr/local/bin/update-theia

# Create status script
cat > /usr/local/bin/theia-status << 'EOF'
#!/bin/bash
cd /opt/theia-app
echo "=== Theia IDE Status ==="
echo ""
echo "Container Status:"
docker-compose ps
echo ""
echo "Service Status:"
systemctl status theia-ide.service --no-pager
echo ""
echo "Workspace Usage:"
du -sh /home/theia-workspace
echo ""
echo "Container Logs (last 20 lines):"
docker-compose logs --tail=20
EOF
chmod +x /usr/local/bin/theia-status

# Print summary
log_info "=========================================="
log_info "Theia IDE Deployment Complete!"
log_info "=========================================="
echo ""
echo "Access your IDE at: https://$DOMAIN"
echo ""
echo "Important Information:"
echo "- Project directory: $PROJECT_DIR"
echo "- GitHub repository: $GITHUB_REPO"
echo "- Persistent workspace: $THEIA_WORKSPACE"
echo "- Container will auto-restart on crashes"
echo "- Container will auto-start on server reboot"
echo ""
echo "Useful Commands:"
echo "- Check status: theia-status"
echo "- View logs: docker-compose logs -f"
echo "- Restart: systemctl restart theia-ide"
echo "- Stop: systemctl stop theia-ide"
echo "- Update: update-theia"
echo ""
echo "Security Features Enabled:"
echo "- SSL/TLS with Let's Encrypt"
echo "- Firewall (UFW) configured"
echo "- Fail2ban protection"
echo "- Non-root container execution"
echo "- Rate limiting in Nginx"
echo ""
log_warning "Remember to:"
log_warning "1. Change the email in this script for Let's Encrypt notifications"
log_warning "2. Regularly backup $THEIA_WORKSPACE"
log_warning "3. Monitor disk space usage"
log_warning "4. Keep the system updated with security patches"