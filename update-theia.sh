#!/bin/bash

# Theia IDE Update Script
# This script updates an existing Theia IDE deployment by pulling latest changes from git
# and rebuilding the Docker container while preserving user data

set -e  # Exit on error

# Configuration - These should match your deployment
PROJECT_DIR="/opt/theia-app"
THEIA_WORKSPACE="/home/theia-workspace"
BACKUP_DIR="/var/backups/theia"
MAX_BACKUPS=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if command was successful
check_status() {
    if [ $? -eq 0 ]; then
        log_info "✓ $1 completed successfully"
    else
        log_error "✗ $1 failed"
        exit 1
    fi
}

# Function to create backup
create_backup() {
    local backup_name="theia-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    log_step "Creating backup: ${backup_name}"
    
    # Create backup directory if it doesn't exist
    mkdir -p "${BACKUP_DIR}"
    
    # Backup important files
    mkdir -p "${backup_path}"
    
    # Backup docker-compose.yml
    if [ -f "${PROJECT_DIR}/docker-compose.yml" ]; then
        cp "${PROJECT_DIR}/docker-compose.yml" "${backup_path}/"
        log_info "Backed up docker-compose.yml"
    fi
    
    # Backup .env file
    if [ -f "${PROJECT_DIR}/.env" ]; then
        cp "${PROJECT_DIR}/.env" "${backup_path}/"
        log_info "Backed up .env file"
    fi
    
    # Backup Dockerfile
    if [ -f "${PROJECT_DIR}/Dockerfile" ]; then
        cp "${PROJECT_DIR}/Dockerfile" "${backup_path}/"
        log_info "Backed up Dockerfile"
    fi
    
    # Store current git commit hash for rollback
    cd "${PROJECT_DIR}"
    git rev-parse HEAD > "${backup_path}/git-commit.txt"
    log_info "Saved current git commit: $(cat ${backup_path}/git-commit.txt)"
    
    # Create a compressed archive of the backup
    tar -czf "${backup_path}.tar.gz" -C "${BACKUP_DIR}" "${backup_name}"
    rm -rf "${backup_path}"
    
    log_info "Backup created: ${backup_path}.tar.gz"
    
    # Clean up old backups (keep only MAX_BACKUPS most recent)
    log_info "Cleaning up old backups (keeping ${MAX_BACKUPS} most recent)"
    ls -t "${BACKUP_DIR}"/theia-backup-*.tar.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
    
    echo "${backup_name}" > /tmp/last_backup_name.txt
}

# Function to rollback to previous version
rollback() {
    log_warning "Rolling back to previous version..."
    
    if [ ! -f /tmp/last_backup_name.txt ]; then
        log_error "No backup information found. Cannot rollback."
        exit 1
    fi
    
    local backup_name=$(cat /tmp/last_backup_name.txt)
    local backup_path="${BACKUP_DIR}/${backup_name}.tar.gz"
    
    if [ ! -f "${backup_path}" ]; then
        log_error "Backup file not found: ${backup_path}"
        exit 1
    fi
    
    log_info "Restoring from backup: ${backup_name}"
    
    # Extract backup
    tar -xzf "${backup_path}" -C "${BACKUP_DIR}"
    
    # Restore git commit
    if [ -f "${BACKUP_DIR}/${backup_name}/git-commit.txt" ]; then
        cd "${PROJECT_DIR}"
        local commit=$(cat "${BACKUP_DIR}/${backup_name}/git-commit.txt")
        git reset --hard "${commit}"
        log_info "Restored git to commit: ${commit}"
    fi
    
    # Restore configuration files
    for file in docker-compose.yml .env Dockerfile; do
        if [ -f "${BACKUP_DIR}/${backup_name}/${file}" ]; then
            cp "${BACKUP_DIR}/${backup_name}/${file}" "${PROJECT_DIR}/"
            log_info "Restored ${file}"
        fi
    done
    
    # Clean up extracted backup
    rm -rf "${BACKUP_DIR}/${backup_name}"
    
    # Rebuild and restart
    cd "${PROJECT_DIR}"
    docker-compose build
    docker-compose up -d
    
    log_info "Rollback completed"
}

# Function to check container health
check_health() {
    log_step "Checking container health..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker-compose ps | grep -q "healthy"; then
            log_info "Container is healthy"
            return 0
        elif docker-compose ps | grep -q "unhealthy"; then
            log_error "Container is unhealthy"
            return 1
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo ""
    log_error "Container health check timed out"
    return 1
}

# Function to show update summary
show_summary() {
    log_info "==========================================="
    log_info "Update Summary"
    log_info "==========================================="
    
    # Show git log of changes
    cd "${PROJECT_DIR}"
    log_info "Changes applied:"
    git log --oneline -n 5
    
    # Show container status
    log_info "\nContainer Status:"
    docker-compose ps
    
    # Show disk usage
    log_info "\nWorkspace Usage:"
    du -sh "${THEIA_WORKSPACE}" 2>/dev/null || echo "Unable to check workspace usage"
}

# Main execution starts here

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Check if project directory exists
if [ ! -d "${PROJECT_DIR}" ]; then
    log_error "Project directory not found: ${PROJECT_DIR}"
    log_error "Please ensure Theia IDE is deployed using deploy-theia.sh first"
    exit 1
fi

# Parse command line arguments
FORCE_UPDATE=false
SKIP_BACKUP=false
NO_CACHE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --rollback)
            rollback
            exit 0
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force         Force update even if no new changes"
            echo "  --skip-backup   Skip creating backup before update"
            echo "  --no-cache      Build Docker image without cache"
            echo "  --rollback      Rollback to previous version"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

log_info "==========================================="
log_info "Starting Theia IDE Update Process"
log_info "==========================================="

# Change to project directory
cd "${PROJECT_DIR}"

# Check current status
log_step "Checking current deployment status..."
if docker-compose ps | grep -q "Up"; then
    log_info "Theia IDE is currently running"
else
    log_warning "Theia IDE is not running or partially running"
fi

# Store current commit
CURRENT_COMMIT=$(git rev-parse HEAD)
log_info "Current commit: ${CURRENT_COMMIT}"

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    log_warning "Uncommitted changes detected in ${PROJECT_DIR}"
    if [ "$FORCE_UPDATE" != true ]; then
        read -p "Do you want to stash these changes and continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Update cancelled"
            exit 1
        fi
        git stash push -m "Auto-stash before update $(date +%Y%m%d-%H%M%S)"
        log_info "Changes stashed"
    fi
fi

# Fetch latest changes from remote
log_step "Fetching latest changes from remote repository..."
git fetch origin

# Check if there are updates
REMOTE_COMMIT=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)
if [ "${CURRENT_COMMIT}" = "${REMOTE_COMMIT}" ] && [ "$FORCE_UPDATE" != true ]; then
    log_info "Already up to date (commit: ${CURRENT_COMMIT})"
    log_info "Use --force to rebuild anyway"
    exit 0
fi

log_info "Updates available: ${CURRENT_COMMIT:0:7} -> ${REMOTE_COMMIT:0:7}"

# Create backup unless skipped
if [ "$SKIP_BACKUP" != true ]; then
    create_backup
else
    log_warning "Skipping backup (--skip-backup specified)"
fi

# Stop the current container
log_step "Stopping Theia IDE container..."
docker-compose down
check_status "Container stop"

# Pull latest changes
log_step "Pulling latest changes from repository..."
git pull origin main 2>/dev/null || git pull origin master
check_status "Git pull"

NEW_COMMIT=$(git rev-parse HEAD)
log_info "Updated to commit: ${NEW_COMMIT}"

# Check if package.json exists
if [ ! -f "package.json" ]; then
    log_error "package.json not found after update"
    if [ "$SKIP_BACKUP" != true ]; then
        log_warning "Attempting rollback..."
        rollback
    fi
    exit 1
fi

# Build Docker image
log_step "Building Docker image..."
if [ "$NO_CACHE" = true ]; then
    log_info "Building without cache (--no-cache specified)"
    docker-compose build --no-cache
else
    docker-compose build
fi

if [ $? -ne 0 ]; then
    log_error "Docker build failed"
    if [ "$SKIP_BACKUP" != true ]; then
        log_warning "Attempting rollback..."
        rollback
    fi
    exit 1
fi

log_info "Docker image built successfully"

# Start the updated container
log_step "Starting updated Theia IDE container..."
docker-compose up -d
check_status "Container start"

# Wait for container to be healthy
if check_health; then
    log_info "✓ Update completed successfully!"
    
    # Show summary
    show_summary
    
    # Clean up temp files
    rm -f /tmp/last_backup_name.txt
    
    log_info "==========================================="
    log_info "Theia IDE has been updated successfully!"
    log_info "==========================================="
    echo ""
    echo "You can access your IDE at the configured domain"
    echo "To view logs: docker-compose logs -f"
    echo "To check status: docker-compose ps"
    echo ""
    
    if [ "$SKIP_BACKUP" != true ]; then
        echo "If you encounter issues, you can rollback using:"
        echo "  $0 --rollback"
    fi
else
    log_error "Container health check failed after update"
    
    if [ "$SKIP_BACKUP" != true ]; then
        read -p "Do you want to rollback to the previous version? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rollback
        else
            log_warning "Not rolling back. Container may be in an unstable state."
            log_warning "You can manually rollback later using: $0 --rollback"
        fi
    else
        log_warning "Cannot rollback (backup was skipped)"
        log_error "Container may be in an unstable state"
    fi
    
    exit 1
fi