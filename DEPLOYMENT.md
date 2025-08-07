# CodeEditor - Docker Deployment Guide

This guide explains how to deploy your CodeEditor application using Docker on any server or droplet.

## Prerequisites

- Docker (version 20.10+ recommended)
- Docker Compose (version 2.0+ recommended)
- At least 2GB RAM and 2GB disk space

## Quick Start

### Method 1: Using Docker Compose (Recommended)

1. **Clone/Upload your project** to the server:
   ```bash
   # If using git
   git clone <your-repo-url>
   cd codeeditor-app
   
   # Or upload the project files manually
   ```

2. **Build and run** with Docker Compose:
   ```bash
   docker-compose up -d --build
   ```

3. **Access your CodeEditor IDE** at:
   ```
   http://your-server-ip:3000
   ```

### Method 2: Using Docker Commands

1. **Build the Docker image**:
   ```bash
   docker build -t codeeditor-app .
   ```

2. **Run the container**:
   ```bash
   docker run -d \
     --name codeeditor-app \
     -p 3000:3000 \
     --restart unless-stopped \
     codeeditor-app
   ```

## Server Setup (Ubuntu/Debian Example)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Logout and login again for group changes to take effect
```

## Configuration Options

### Port Configuration
- Default port: `3000`
- To change port, modify the `docker-compose.yml` file:
  ```yaml
  ports:
    - "8080:3000"  # Change 8080 to your desired port
  ```

### Persistent Workspace
- The compose file includes a volume for persistent file storage
- Files will be saved in `./workspace` directory on the host

### Environment Variables
Add environment variables in `docker-compose.yml`:
```yaml
environment:
  - NODE_ENV=production
  - CODEEDITOR_DEFAULT_PLUGINS=local-dir:/app/plugins
```

## Management Commands

```bash
# View logs
docker-compose logs -f

# Stop the application
docker-compose down

# Restart the application
docker-compose restart

# Update and rebuild
docker-compose down
docker-compose up -d --build

# Check status
docker-compose ps
```

## Firewall Configuration

Make sure port 3000 (or your custom port) is open:

```bash
# Ubuntu/Debian with ufw
sudo ufw allow 3000

# CentOS/RHEL with firewalld
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload
```

## Production Considerations

1. **Reverse Proxy**: Consider using Nginx or Traefik for SSL and domain mapping
2. **Resource Limits**: Add resource limits in docker-compose.yml:
   ```yaml
   deploy:
     resources:
       limits:
         memory: 2G
         cpus: '1.0'
   ```
3. **Backup**: Regularly backup the `./workspace` directory
4. **Monitoring**: Set up monitoring for container health and resource usage

## Troubleshooting

### Container won't start
```bash
# Check logs
docker-compose logs

# Check if port is already in use
sudo netstat -tlnp | grep :3000
```

### Performance Issues
```bash
# Check resource usage
docker stats

# Increase memory limit in docker-compose.yml
```

### Build Issues
```bash
# Clean build
docker-compose down
docker system prune -f
docker-compose up -d --build --no-cache
```

## Security Notes

- The application runs as a non-root user inside the container
- Consider setting up SSL/TLS with a reverse proxy
- Regularly update the base Node.js image for security patches
- Monitor container logs for suspicious activity