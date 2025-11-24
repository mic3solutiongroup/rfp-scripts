#!/bin/bash

set -euo pipefail

# Script configuration
CONFIG_FILE="/etc/n8s/config.env"
SCRIPT_PATH="/usr/local/bin/n8s"
REPO_URL="https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/n8s.sh"

# Default values
N8N_DIR="${HOME}/rfp/n8n"
NGINX_CONF="/etc/nginx/sites-available/n8s-router.conf"
NGINX_CONF_ENABLED="/etc/nginx/sites-enabled/n8s-router.conf"
ROUTES_DIR="/etc/nginx/routes-n8s"
NGINX_PORT_DEFAULT=1440
SERVER_IP_DEFAULT="localhost"

# Global variables
declare -gA PORT_MAPPINGS || true
declare -ga NGINX_PORTS || true
INTERACTIVE_MODE=true

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. Some operations might need user context."
        return 0
    fi
    return 0
}

# Load or create configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading existing configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        # Check if running interactively
        if [[ "$INTERACTIVE_MODE" == "true" ]]; then
            log_info "No existing config found. Setting up initial configuration..."

            # Get external IP with fallback
            if SERVER_IP=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 ipinfo.io/ip || echo "$SERVER_IP_DEFAULT"); then
                log_info "Detected server IP: $SERVER_IP"
            else
                SERVER_IP="$SERVER_IP_DEFAULT"
                log_warning "Could not detect external IP, using: $SERVER_IP"
            fi

            read -p "Enter nginx port to listen on [${NGINX_PORT_DEFAULT}]: " input_port
            NGINX_PORT="${input_port:-$NGINX_PORT_DEFAULT}"

            read -p "Enter n8n directory [${N8N_DIR}]: " input_dir
            N8N_DIR="${input_dir:-$N8N_DIR}"

            # Initialize other variables
            N8N_INSTALLED=false
            DOCKER_INSTALLED=false
            NGINX_INSTALLED=false
            # PORT_MAPPINGS is already declared globally, just clear it
            PORT_MAPPINGS=()

            save_config
        else
            # Non-interactive mode - use defaults
            log_info "No config found. Using default values..."

            # Get external IP with fallback
            if SERVER_IP=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null); then
                log_info "Detected server IP: $SERVER_IP"
            else
                SERVER_IP="$SERVER_IP_DEFAULT"
                log_info "Using default IP: $SERVER_IP"
            fi

            NGINX_PORT="$NGINX_PORT_DEFAULT"
            N8N_DIR="$N8N_DIR"
            N8N_INSTALLED=false
            DOCKER_INSTALLED=false
            NGINX_INSTALLED=false
            # PORT_MAPPINGS is already declared globally, just clear it
            PORT_MAPPINGS=()

            log_info "Using nginx port: $NGINX_PORT"
            log_info "Using n8n directory: $N8N_DIR"

            save_config
        fi
    fi

    # Set defaults if not defined
    : "${NGINX_PORT:=$NGINX_PORT_DEFAULT}"
    : "${SERVER_IP:=$(curl -s --max-time 5 ifconfig.me || echo "$SERVER_IP_DEFAULT")}"
    : "${N8N_DIR:=$N8N_DIR}"
    : "${ROUTES_DIR:=$ROUTES_DIR}"
    : "${NGINX_CONF:=$NGINX_CONF}"
    : "${N8N_INSTALLED:=false}"
    : "${DOCKER_INSTALLED:=false}"
    : "${NGINX_INSTALLED:=false}"

    # Initialize NGINX_PORTS if not set
    if [[ -z "${NGINX_PORTS+x}" ]] || [[ "${#NGINX_PORTS[@]}" -eq 0 ]]; then
        NGINX_PORTS=("$NGINX_PORT")
    fi

    # Ensure main NGINX_PORT is in NGINX_PORTS
    if [[ ! " ${NGINX_PORTS[@]} " =~ " ${NGINX_PORT} " ]]; then
        NGINX_PORTS+=("$NGINX_PORT")
    fi

    # Verify actual system state (override config if needed)
    if check_docker; then
        if [[ "$DOCKER_INSTALLED" != "true" ]]; then
            log_info "Docker detected on system (updating config)"
            DOCKER_INSTALLED=true
            save_config
        fi
    fi

    if command -v nginx &> /dev/null; then
        if [[ "$NGINX_INSTALLED" != "true" ]]; then
            log_info "nginx detected on system (updating config)"
            NGINX_INSTALLED=true
            save_config
        fi
    fi

    # Check if n8n container exists
    if check_docker && docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^n8n$"; then
        if [[ "$N8N_INSTALLED" != "true" ]]; then
            log_info "n8n container detected on system (updating config)"
            N8N_INSTALLED=true
            save_config
        fi
    fi
}

# Save configuration
save_config() {
    log_info "Saving configuration to $CONFIG_FILE"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    {
        echo "NGINX_PORT=$NGINX_PORT"
        echo "SERVER_IP='$SERVER_IP'"
        echo "N8N_INSTALLED=$N8N_INSTALLED"
        echo "DOCKER_INSTALLED=$DOCKER_INSTALLED"
        echo "NGINX_INSTALLED=$NGINX_INSTALLED"
        echo "N8N_DIR='$N8N_DIR'"
        echo "ROUTES_DIR='$ROUTES_DIR'"
        echo "NGINX_CONF='$NGINX_CONF'"

        # Save NGINX_PORTS array
        if [[ "${#NGINX_PORTS[@]}" -gt 0 ]]; then
            echo "NGINX_PORTS=("
            for nginx_port in "${NGINX_PORTS[@]}"; do
                echo "  $nginx_port"
            done
            echo ")"
        else
            echo "NGINX_PORTS=()"
        fi

        # Always initialize PORT_MAPPINGS as associative array
        if [[ "${!PORT_MAPPINGS[@]+isset}" == "isset" ]] && [[ ${#PORT_MAPPINGS[@]} -gt 0 ]]; then
            echo "declare -gA PORT_MAPPINGS=("
            for key in "${!PORT_MAPPINGS[@]}"; do
                echo "  ['$key']='${PORT_MAPPINGS[$key]}'"
            done
            echo ")"
        else
            echo "declare -gA PORT_MAPPINGS=()"
        fi
    } > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

# Update script from repository
update_script() {
    log_info "Updating n8s script from repository..."
    if curl -fsSL "$REPO_URL" -o /tmp/n8s_new.sh; then
        chmod +x /tmp/n8s_new.sh
        if mv /tmp/n8s_new.sh "$SCRIPT_PATH"; then
            log_success "Update completed successfully"
            exit 0
        else
            log_error "Failed to move updated script to $SCRIPT_PATH"
            exit 1
        fi
    else
        log_error "Update failed - could not download from $REPO_URL"
        exit 1
    fi
}

# Install Docker with comprehensive error handling
install_docker() {
    log_info "Starting Docker installation..."
    
    if check_docker; then
        log_success "Docker is already installed and running"
        DOCKER_INSTALLED=true
        save_config
        return 0
    fi

    export DEBIAN_FRONTEND=noninteractive

    # Update package list
    log_info "Updating package lists..."
    if ! apt update; then
        log_error "Failed to update package lists"
        return 1
    fi

    # Install prerequisites
    log_info "Installing prerequisites..."
    if ! apt install -y ca-certificates curl gnupg lsb-release; then
        log_error "Failed to install prerequisites"
        return 1
    fi

    # Add Docker's official GPG key
    log_info "Adding Docker's GPG key..."
    mkdir -p /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log_error "Failed to download Docker GPG key"
        return 1
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    log_info "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    if ! apt update; then
        log_error "Failed to update package lists with Docker repository"
        return 1
    fi

    # Install Docker
    log_info "Installing Docker packages..."
    if ! apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_warning "First attempt failed, trying alternative method..."
        
        # Try installing docker.io as fallback
        if ! apt install -y docker.io; then
            log_error "Docker installation failed completely"
            return 1
        fi
    fi

    # Start and enable Docker service
    log_info "Starting Docker service..."
    systemctl enable docker 2>/dev/null || true
    if ! systemctl start docker; then
        log_warning "Failed to start Docker service, attempting manual start..."
        dockerd & 2>/dev/null || true
        sleep 5
    fi

    # Add user to docker group
    log_info "Adding user to docker group..."
    if ! usermod -aG docker "$USER" 2>/dev/null; then
        log_warning "Could not add user to docker group. You may need to run Docker commands with sudo."
    fi

    # Verify installation
    if check_docker; then
        log_success "Docker installed successfully"
        DOCKER_INSTALLED=true
        save_config
        return 0
    else
        log_error "Docker installation verification failed"
        return 1
    fi
}

# Reinstall Docker (complete removal and fresh install)
reinstall_docker() {
    log_warning "=== Docker Reinstallation ==="
    echo ""
    echo "This will:"
    echo "  1. Stop all Docker containers"
    echo "  2. Remove all Docker packages"
    echo "  3. Clean up Docker directories"
    echo "  4. Reinstall Docker from scratch"
    echo ""
    log_error "WARNING: This will stop all running containers!"
    echo ""
    read -p "Continue with Docker reinstallation? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_info "Reinstallation cancelled"
        return 1
    fi

    # Stop Docker service
    log_info "Stopping Docker service..."
    systemctl stop docker 2>/dev/null || true
    systemctl stop docker.socket 2>/dev/null || true
    pkill -9 dockerd 2>/dev/null || true

    # Remove Docker packages
    log_info "Removing Docker packages..."
    apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true

    # Clean up Docker directories
    log_info "Cleaning up Docker directories..."
    rm -rf /var/lib/docker 2>/dev/null || true
    rm -rf /var/lib/containerd 2>/dev/null || true
    rm -rf /etc/docker 2>/dev/null || true
    rm -rf /var/run/docker.sock 2>/dev/null || true
    rm -rf /usr/local/bin/docker-compose 2>/dev/null || true

    # Remove Docker repository files
    log_info "Removing Docker repository configurations..."
    rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
    rm -f /etc/apt/keyrings/docker.gpg 2>/dev/null || true

    log_success "Docker removed successfully"
    echo ""

    # Reinstall Docker using get.docker.com script
    log_info "Reinstalling Docker using official installation script..."

    if ! curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
        log_error "Failed to download Docker installation script"
        return 1
    fi

    if ! sh /tmp/get-docker.sh; then
        log_error "Docker installation failed"
        rm -f /tmp/get-docker.sh
        return 1
    fi

    rm -f /tmp/get-docker.sh

    # Start and enable Docker
    log_info "Starting Docker service..."
    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
    sleep 3

    # Verify installation
    if check_docker; then
        log_success "Docker reinstalled successfully!"
        docker --version
        DOCKER_INSTALLED=true
        save_config
        return 0
    else
        log_error "Docker reinstallation completed but verification failed"
        log_info "You may need to reboot the system"
        return 1
    fi
}

# Check nginx status
check_nginx() {
    # Check if nginx command exists
    if ! command -v nginx &> /dev/null; then
        return 1
    fi

    # Check if nginx is running (process or service)
    if pgrep -x nginx > /dev/null 2>&1; then
        return 0
    fi

    if systemctl is-active --quiet nginx 2>/dev/null; then
        return 0
    fi

    # nginx exists but not running
    return 1
}

# Check Docker status
check_docker() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi

    # Check if Docker is running via systemctl
    if systemctl is-active --quiet docker 2>/dev/null; then
        # Test Docker functionality
        if docker info &> /dev/null; then
            return 0
        fi
    fi

    # Try to start Docker if not running
    if systemctl start docker 2>/dev/null; then
        sleep 2
        if docker info &> /dev/null; then
            return 0
        fi
    fi

    # Check if Docker daemon is running (even without systemd)
    if docker info &> /dev/null; then
        return 0
    fi

    return 1
}

# Start Docker service
start_docker() {
    log_info "Starting Docker service..."

    if check_docker; then
        log_success "Docker is already running"
        return 0
    fi

    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        return 1
    fi

    # Try to enable and start Docker
    if systemctl enable docker 2>/dev/null; then
        log_success "Docker service enabled"
    fi

    if systemctl start docker 2>/dev/null; then
        sleep 3
        if check_docker; then
            log_success "Docker started successfully"
            DOCKER_INSTALLED=true
            save_config
            return 0
        fi
    fi

    # Try alternative start method
    log_warning "Attempting alternative Docker start method..."
    dockerd & 2>/dev/null || true
    sleep 5

    if check_docker; then
        log_success "Docker started successfully"
        DOCKER_INSTALLED=true
        save_config
        return 0
    else
        log_error "Failed to start Docker"
        return 1
    fi
}

# Start nginx service
start_nginx() {
    log_info "Starting nginx service..."

    if check_nginx; then
        log_success "nginx is already running"
        return 0
    fi

    if ! command -v nginx &> /dev/null; then
        log_error "nginx is not installed. Please install nginx first."
        return 1
    fi

    # Try to enable and start nginx
    if systemctl enable nginx 2>/dev/null; then
        log_success "nginx service enabled"
    fi

    if systemctl start nginx 2>/dev/null; then
        sleep 2
        if check_nginx; then
            log_success "nginx started successfully"
            NGINX_INSTALLED=true
            save_config
            return 0
        fi
    fi

    # Try direct nginx start (for non-systemd systems)
    log_warning "Attempting direct nginx start..."
    if nginx 2>/dev/null; then
        sleep 2
        if check_nginx; then
            log_success "nginx started successfully"
            NGINX_INSTALLED=true
            save_config
            return 0
        fi
    fi

    log_error "Failed to start nginx. It may be managed by a control panel."
    log_info "Please start nginx through your control panel interface."
    return 1
}

# Install and configure nginx
install_nginx() {
    log_info "Starting nginx installation..."

    # Check if nginx is already installed
    if command -v nginx &> /dev/null; then
        log_success "nginx is already installed"
        NGINX_INSTALLED=true

        # Ensure nginx is running
        if ! check_nginx; then
            log_info "nginx is installed but not running. Starting nginx service..."
            if ! systemctl start nginx 2>/dev/null; then
                log_warning "Could not start nginx via systemctl. It may be managed by a control panel."
            fi
        else
            log_success "nginx is running"
        fi
    else
        log_info "Installing nginx..."
        if ! apt update || ! apt install -y nginx; then
            log_error "Failed to install nginx"
            return 1
        fi
        NGINX_INSTALLED=true
        systemctl enable nginx 2>/dev/null || true

        # Start nginx
        if ! systemctl start nginx 2>/dev/null; then
            log_warning "Could not start nginx via systemctl"
        fi
    fi

    # Generate nginx configuration
    generate_nginx_config
}

# Reinstall nginx (complete removal and fresh install)
reinstall_nginx() {
    log_warning "=== nginx Reinstallation ==="
    echo ""
    echo "This will:"
    echo "  1. Stop nginx service"
    echo "  2. Remove nginx packages"
    echo "  3. Clean up nginx configurations"
    echo "  4. Reinstall nginx"
    echo "  5. Regenerate configurations"
    echo ""
    log_warning "NOTE: All custom nginx configurations will be lost!"
    log_info "n8s routes will be regenerated automatically"
    echo ""
    read -p "Continue with nginx reinstallation? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_info "Reinstallation cancelled"
        return 1
    fi

    # Backup current routes
    log_info "Backing up n8s routes..."
    if [[ -d "$ROUTES_DIR" ]]; then
        cp -r "$ROUTES_DIR" /tmp/n8s-routes-backup 2>/dev/null || true
        log_success "Routes backed up to /tmp/n8s-routes-backup"
    fi

    # Stop nginx service
    log_info "Stopping nginx service..."
    systemctl stop nginx 2>/dev/null || true
    pkill -9 nginx 2>/dev/null || true

    # Remove nginx packages
    log_info "Removing nginx packages..."
    apt-get remove -y nginx nginx-common nginx-core 2>/dev/null || true
    apt-get purge -y nginx nginx-common nginx-core 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true

    # Clean up nginx directories and configs
    log_info "Cleaning up nginx configurations..."
    rm -rf /etc/nginx 2>/dev/null || true
    rm -rf /var/log/nginx 2>/dev/null || true
    rm -rf /var/www/html 2>/dev/null || true
    rm -rf /usr/share/nginx 2>/dev/null || true

    log_success "nginx removed successfully"
    echo ""

    # Reinstall nginx
    log_info "Reinstalling nginx..."
    export DEBIAN_FRONTEND=noninteractive

    if ! apt-get update; then
        log_error "Failed to update package lists"
        return 1
    fi

    if ! apt-get install -y nginx; then
        log_error "nginx installation failed"
        return 1
    fi

    # Start and enable nginx
    log_info "Starting nginx service..."
    systemctl enable nginx 2>/dev/null || true
    systemctl start nginx 2>/dev/null || true
    sleep 2

    # Verify installation
    if command -v nginx &> /dev/null; then
        log_success "nginx reinstalled successfully!"
        nginx -v
        NGINX_INSTALLED=true
        save_config

        # Regenerate nginx configuration
        log_info "Regenerating nginx configuration..."
        generate_nginx_config

        # Restore routes if backup exists
        if [[ -d /tmp/n8s-routes-backup ]]; then
            log_info "Restoring n8s routes..."
            mkdir -p "$ROUTES_DIR"
            cp -r /tmp/n8s-routes-backup/* "$ROUTES_DIR/" 2>/dev/null || true
            rm -rf /tmp/n8s-routes-backup

            # Reload nginx with restored routes
            if nginx -t 2>/dev/null; then
                systemctl reload nginx
                log_success "Routes restored successfully"
            else
                log_warning "Some routes may need to be reconfigured"
            fi
        fi

        return 0
    else
        log_error "nginx reinstallation verification failed"
        return 1
    fi
}

# Generate nginx configuration
generate_nginx_config() {
    log_info "Generating nginx configuration for ${#NGINX_PORTS[@]} port(s)..."

    mkdir -p "$ROUTES_DIR"

    # Remove old conflicting configurations
    rm -f /etc/nginx/sites-available/8443-router.conf 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/8443-router.conf 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    # Create nginx configuration with server blocks for each port
    {
        for nginx_port in "${NGINX_PORTS[@]}"; do
            cat << NGXEOF
server {
    listen ${nginx_port} $([ "$nginx_port" == "${NGINX_PORTS[0]}" ] && echo "default_server" || echo "");
    listen [::]:${nginx_port} $([ "$nginx_port" == "${NGINX_PORTS[0]}" ] && echo "default_server" || echo "");
    server_name _;
    client_max_body_size 100M;

    # Health check endpoint
    location = /health {
        return 200 'healthy\n';
        add_header Content-Type text/plain;
    }

    # Root endpoint
    location = / {
        return 200 'n8s router is running on port ${nginx_port}\n';
        add_header Content-Type text/plain;
    }

    # Include route configurations for this port
    include ${ROUTES_DIR}/${nginx_port}-*.conf;
}

NGXEOF
        done
    } > "$NGINX_CONF"

    # Enable site
    ln -sf "$NGINX_CONF" "$NGINX_CONF_ENABLED"

    # Test and reload nginx
    if nginx -t 2>/dev/null; then
        systemctl reload nginx 2>/dev/null || true
        log_success "nginx configuration updated successfully for ports: ${NGINX_PORTS[*]}"
    else
        log_error "nginx configuration test failed"
        nginx -t
        return 1
    fi
}

# Write n8n route configuration (interactive)
write_n8n_route() {
    mkdir -p "$ROUTES_DIR"

    echo ""
    echo "=== n8n Access Configuration ==="
    echo "How do you want to access n8n via nginx?"
    echo ""
    echo "1) Direct Access (Root Path)"
    echo "   External: http://${SERVER_IP}:${NGINX_PORT}/"
    echo "   nginx forwards root path directly to n8n"
    echo ""
    echo "2) Path-Based Access (Subpath)"
    echo "   External: http://${SERVER_IP}:${NGINX_PORT}/n8n/"
    echo "   nginx forwards a subpath to n8n"
    echo ""
    read -p "Select option (1 or 2) [2]: " access_type
    access_type="${access_type:-2}"

    # n8n always runs on localhost:5678 internally
    local n8n_internal_port=5678

    if [[ "$access_type" == "1" ]]; then
        # Direct Access - Root Path
        log_info "Configuring direct access (root path)..."

        # Create nginx config for root path
        cat > "$ROUTES_DIR/n8n.conf" << 'N8NEOF'
location / {
    proxy_pass http://127.0.0.1:5678/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;

    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 300s;
    proxy_connect_timeout 75s;
}
N8NEOF

        PORT_MAPPINGS["${NGINX_PORT}:/"]="$n8n_internal_port"
        N8N_BASE_PATH="/"
        log_success "Direct access configured: http://${SERVER_IP}:${NGINX_PORT}/ -> http://127.0.0.1:${n8n_internal_port}/"

    else
        # Path-Based Access - Subpath
        read -p "Enter nginx subpath for n8n [/n8n/]: " n8n_path
        n8n_path="${n8n_path:-/n8n/}"

        # Ensure path starts and ends with /
        [[ ! "$n8n_path" =~ ^/ ]] && n8n_path="/$n8n_path"
        [[ ! "$n8n_path" =~ /$ ]] && n8n_path="$n8n_path/"

        log_info "Configuring path-based access (subpath: ${n8n_path})..."

        # Create nginx config for subpath with port-specific filename
        cat > "$ROUTES_DIR/${NGINX_PORT}-n8n.conf" << N8NEOF
location ${n8n_path} {
    proxy_pass http://127.0.0.1:${n8n_internal_port}/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;

    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 300s;
    proxy_connect_timeout 75s;
}

location = ${n8n_path%/} {
    return 301 ${n8n_path};
}
N8NEOF

        PORT_MAPPINGS["${NGINX_PORT}:$n8n_path"]="$n8n_internal_port"
        N8N_BASE_PATH="$n8n_path"
        log_success "Path-based access configured: http://${SERVER_IP}:${NGINX_PORT}${n8n_path} -> http://127.0.0.1:${n8n_internal_port}/"
    fi

    return 0  # Signal that nginx reload is needed
}

# Install n8n
install_n8n() {
    log_info "Starting n8n installation..."
    
    if ! check_docker; then
        log_error "Docker not available. Please install Docker first."
        return 1
    fi

    # Ensure nginx is installed and configured
    if ! install_nginx; then
        log_error "nginx installation failed"
        return 1
    fi

    # Create n8n directory
    log_info "Setting up n8n in: $N8N_DIR"
    mkdir -p "$N8N_DIR"

    # Check for existing installation
    if [[ -f "$N8N_DIR/docker-compose.yml" ]]; then
        read -p "n8n docker-compose.yml exists. Overwrite? (y/n): " overwrite
        if [[ "$overwrite" != "y" ]]; then
            log_warning "Skipping n8n installation"
            return 1
        fi
    fi

    # Create docker volume
    log_info "Creating Docker volume for n8n..."
    docker volume create n8n_data 2>/dev/null || log_warning "Volume might already exist"

    # Ask about access mode FIRST (before generating docker-compose)
    echo ""
    echo "=== n8n Access Configuration ==="
    echo "How do you want to access n8n via nginx?"
    echo ""
    echo "1) Direct Access (Root Path)"
    echo "   External: http://${SERVER_IP}:${NGINX_PORT}/"
    echo "   nginx forwards root path directly to n8n"
    echo ""
    echo "2) Path-Based Access (Subpath)"
    echo "   External: http://${SERVER_IP}:${NGINX_PORT}/n8n/"
    echo "   nginx forwards a subpath to n8n"
    echo ""
    read -p "Select option (1 or 2) [2]: " access_type
    access_type="${access_type:-2}"

    # Set base path based on choice
    if [[ "$access_type" == "1" ]]; then
        N8N_BASE_PATH="/"
        N8N_EXTERNAL_URL="http://${SERVER_IP}:${NGINX_PORT}/"
    else
        read -p "Enter nginx subpath for n8n [/n8n/]: " n8n_path
        n8n_path="${n8n_path:-/n8n/}"
        # Ensure path starts and ends with /
        [[ ! "$n8n_path" =~ ^/ ]] && n8n_path="/$n8n_path"
        [[ ! "$n8n_path" =~ /$ ]] && n8n_path="$n8n_path/"
        N8N_BASE_PATH="$n8n_path"
        N8N_EXTERNAL_URL="http://${SERVER_IP}:${NGINX_PORT}${n8n_path}"
    fi

    # Ask about network mode
    echo ""
    echo "=== Docker Network Mode ==="
    echo "1) Host network (recommended - avoids port permission issues)"
    echo "2) Bridge network (isolated networking)"
    echo ""
    read -p "Select network mode (1 or 2) [1]: " network_mode_choice
    network_mode_choice="${network_mode_choice:-1}"

    # Create docker-compose file
    log_info "Creating docker-compose configuration..."

    if [[ "$network_mode_choice" == "1" ]]; then
        # Host network mode
        log_info "Using host network mode..."
        cat > "$N8N_DIR/docker-compose.yml" << DCEOF
version: '3.8'

services:
  n8n:
    image: docker.io/n8nio/n8n:1.121.2
    container_name: n8n
    restart: unless-stopped
    network_mode: host
    environment:
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - N8N_HOST=0.0.0.0
      - N8N_BASE_URL=${N8N_BASE_PATH}
      - N8N_EDITOR_BASE_URL=${N8N_EXTERNAL_URL}
      - WEBHOOK_URL=http://${SERVER_IP}:${NGINX_PORT}/
      - N8N_DIAGNOSTICS_ENABLED=false
      - N8N_PUSH_BACKEND=websocket
      - N8N_SECURE_COOKIE=false
      - NODE_ENV=production
      - GENERIC_TIMEZONE=UTC
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
    external: true
DCEOF
    else
        # Bridge network mode
        log_info "Using bridge network mode..."
        cat > "$N8N_DIR/docker-compose.yml" << DCEOF
version: '3.8'

services:
  n8n:
    image: docker.io/n8nio/n8n:1.121.2
    container_name: n8n
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - N8N_HOST=0.0.0.0
      - N8N_BASE_URL=${N8N_BASE_PATH}
      - N8N_EDITOR_BASE_URL=${N8N_EXTERNAL_URL}
      - WEBHOOK_URL=http://${SERVER_IP}:${NGINX_PORT}/
      - N8N_DIAGNOSTICS_ENABLED=false
      - N8N_PUSH_BACKEND=websocket
      - N8N_SECURE_COOKIE=false
      - NODE_ENV=production
      - GENERIC_TIMEZONE=UTC
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n_network

volumes:
  n8n_data:
    external: true

networks:
  n8n_network:
    driver: bridge
DCEOF
    fi

    # Start n8n
    log_info "Starting n8n container..."
    cd "$N8N_DIR"
    
    if docker compose version &> /dev/null; then
        docker compose up -d
    elif command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        log_error "Docker Compose not available"
        return 1
    fi

    # Wait for n8n to start
    log_info "Waiting for n8n to start..."
    for i in {1..30}; do
        if curl -s http://127.0.0.1:5678/healthz > /dev/null; then
            break
        fi
        sleep 2
    done

    # Create nginx route configuration based on earlier choice
    log_info "Configuring nginx reverse proxy..."
    mkdir -p "$ROUTES_DIR"

    if [[ "$access_type" == "1" ]]; then
        # Direct Access - Root Path
        cat > "$ROUTES_DIR/${NGINX_PORT}-n8n.conf" << 'N8NEOF'
location / {
    proxy_pass http://127.0.0.1:5678/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;

    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 300s;
    proxy_connect_timeout 75s;
}
N8NEOF
        PORT_MAPPINGS["${NGINX_PORT}:/"]="5678"
    else
        # Path-Based Access - Subpath
        cat > "$ROUTES_DIR/${NGINX_PORT}-n8n.conf" << N8NEOF
location ${N8N_BASE_PATH} {
    proxy_pass http://127.0.0.1:5678/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;

    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 300s;
    proxy_connect_timeout 75s;
}

location = ${N8N_BASE_PATH%/} {
    return 301 ${N8N_BASE_PATH};
}
N8NEOF
        PORT_MAPPINGS["${NGINX_PORT}:$N8N_BASE_PATH"]="5678"
    fi

    # Reload nginx
    if nginx -t && systemctl reload nginx; then
        log_success "nginx reloaded with n8n configuration"
    else
        log_error "Failed to reload nginx"
    fi

    # Update configuration
    N8N_INSTALLED=true
    save_config

    log_success "n8n installation completed!"
    echo ""
    echo "================================================"
    echo "n8n Access Information:"
    echo "================================================"
    echo ""
    echo "  External: ${N8N_EXTERNAL_URL}"
    echo "  Local:    http://127.0.0.1:5678/"
    echo ""
    echo "  nginx Port: ${NGINX_PORT}"
    echo "  n8n Base Path: ${N8N_BASE_PATH}"
    echo "  Directory: $N8N_DIR"
    echo ""
    echo "================================================"
    echo ""
}

# Reinstall n8n
reinstall_n8n() {
    if ! check_docker; then
        log_error "Docker not available"
        return 1
    fi

    if [[ "${N8N_INSTALLED:-false}" != "true" || ! -f "$N8N_DIR/docker-compose.yml" ]]; then
        log_warning "n8n not installed via this script. Performing fresh install..."
        install_n8n
        return
    fi

    log_warning "This will stop and recreate the n8n container."
    read -p "Continue? (y/n): " confirm
    [[ "$confirm" != "y" ]] && log_info "Reinstall cancelled." && return

    cd "$N8N_DIR" || {
        log_error "Cannot access n8n directory: $N8N_DIR"
        return 1
    }

    # Stop and remove existing container
    log_info "Stopping existing n8n container..."
    if docker compose version &> /dev/null; then
        docker compose down
    else
        docker-compose down
    fi

    # Optionally remove volume
    read -p "Remove n8n data volume? This will delete all workflows! (y/n): " wipe
    if [[ "$wipe" == "y" ]]; then
        log_warning "Removing n8n_data volume..."
        docker volume rm n8n_data 2>/dev/null || log_warning "Volume might not exist"
    fi

    N8N_INSTALLED=false
    save_config

    # Reinstall
    install_n8n
}

# Add custom route
add_route() {
    # Show available nginx ports
    echo "=== Available nginx ports ==="
    for i in "${!NGINX_PORTS[@]}"; do
        echo "$((i+1))) Port ${NGINX_PORTS[$i]}"
    done
    echo "$((${#NGINX_PORTS[@]}+1))) Add a new port"
    echo ""

    read -p "Select nginx port [1]: " port_choice
    port_choice="${port_choice:-1}"

    local nginx_port
    if [[ "$port_choice" == "$((${#NGINX_PORTS[@]}+1))" ]]; then
        # Add new port
        read -p "Enter new nginx port: " nginx_port
        if [[ ! "$nginx_port" =~ ^[0-9]+$ ]]; then
            log_error "Invalid port number"
            return 1
        fi
        NGINX_PORTS+=("$nginx_port")
        save_config
        log_success "Added nginx port: $nginx_port"
        generate_nginx_config
    else
        # Use existing port
        if [[ "$port_choice" -lt 1 || "$port_choice" -gt "${#NGINX_PORTS[@]}" ]]; then
            log_error "Invalid selection"
            return 1
        fi
        nginx_port="${NGINX_PORTS[$((port_choice-1))]}"
    fi

    read -p "Enter nginx path (e.g., /api/): " path
    read -p "Enter internal port: " port
    read -p "Route name (alphanumeric): " name

    # Validate input
    [[ -z "$path" || -z "$port" || -z "$name" ]] && {
        log_error "All fields are required"
        return 1
    }

    [[ ! "$path" =~ ^/ ]] && path="/$path"
    [[ ! "$path" =~ /$ ]] && path="$path/"

    # Sanitize name
    name=$(echo "$name" | tr -cd '[:alnum:]-_')

    mkdir -p "$ROUTES_DIR"

    # Create route configuration with port-specific filename
    cat > "$ROUTES_DIR/${nginx_port}-${name}.conf" << RTEOF
location $path {
    proxy_pass http://127.0.0.1:$port/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_buffering off;
}
RTEOF

    # Test and reload nginx
    if nginx -t && systemctl reload nginx; then
        PORT_MAPPINGS["$nginx_port:$path"]="$port"
        save_config
        log_success "Route added: http://$SERVER_IP:$nginx_port$path -> localhost:$port"
    else
        rm -f "$ROUTES_DIR/${nginx_port}-${name}.conf"
        log_error "Failed to add route - nginx configuration test failed"
        return 1
    fi
}

# List all routes
list_routes() {
    echo "=== Current Configuration ==="
    echo "Primary Port  : $NGINX_PORT"
    echo "Active Ports  : ${NGINX_PORTS[*]}"
    echo "Server IP     : $SERVER_IP"
    echo "Docker Status : $([ "$DOCKER_INSTALLED" = "true" ] && echo "Installed" || echo "Not Installed")"
    echo "nginx Status  : $([ "$NGINX_INSTALLED" = "true" ] && echo "Installed" || echo "Not Installed")"
    echo "n8n Status    : $([ "$N8N_INSTALLED" = "true" ] && echo "Installed" || echo "Not Installed")"
    echo "n8n Directory : $N8N_DIR"
    echo "Routes Dir    : $ROUTES_DIR"
    echo ""

    if [[ ${#PORT_MAPPINGS[@]} -eq 0 ]]; then
        echo "No routes configured"
    else
        echo "=== Configured Routes ==="
        # Group routes by nginx port
        for nginx_port in "${NGINX_PORTS[@]}"; do
            local has_routes=false
            echo ""
            echo "Port $nginx_port:"
            for key in "${!PORT_MAPPINGS[@]}"; do
                # Check if this mapping is for the current nginx port
                if [[ "$key" =~ ^${nginx_port}: ]]; then
                    local path="${key#*:}"
                    local internal_port="${PORT_MAPPINGS[$key]}"
                    echo "  http://$SERVER_IP:$nginx_port$path -> localhost:$internal_port"
                    has_routes=true
                fi
            done
            if [[ "$has_routes" == "false" ]]; then
                echo "  (no routes configured)"
            fi
        done
    fi
}

# Remove route
remove_route() {
    list_routes
    echo ""
    read -p "Enter route name to remove (conf name without .conf): " name

    if [[ -f "$ROUTES_DIR/${name}.conf" ]]; then
        # Find the path from the configuration file to remove from PORT_MAPPINGS
        path=$(grep -o 'location[[:space:]]*[^[:space:]]*' "$ROUTES_DIR/${name}.conf" | awk '{print $2}')
        
        rm -f "$ROUTES_DIR/${name}.conf"
        
        # Remove from PORT_MAPPINGS
        if [[ -n "$path" ]]; then
            unset "PORT_MAPPINGS[$path]"
        fi

        save_config

        if nginx -t && systemctl reload nginx; then
            log_success "Route '$name' removed successfully"
        else
            log_error "Route removed but nginx reload failed"
        fi
    else
        log_error "Route '$name' not found"
    fi
}

# Change settings
change_settings() {
    echo "=== Current Settings ==="
    echo "1. Nginx Port: $NGINX_PORT"
    echo "2. Server IP: $SERVER_IP"
    echo "3. n8n Directory: $N8N_DIR"
    echo ""

    read -p "Enter setting number to change (1-3) or 'c' to cancel: " choice

    case $choice in
        1)
            read -p "Enter new nginx port [$NGINX_PORT]: " new_port
            [[ -n "${new_port:-}" ]] && NGINX_PORT="$new_port"
            ;;
        2)
            read -p "Enter server IP [$SERVER_IP]: " new_ip
            [[ -n "${new_ip:-}" ]] && SERVER_IP="$new_ip"
            ;;
        3)
            read -p "Enter n8n directory [$N8N_DIR]: " new_dir
            [[ -n "${new_dir:-}" ]] && N8N_DIR="$new_dir"
            ;;
        c|C)
            log_info "Settings change cancelled"
            return
            ;;
        *)
            log_error "Invalid choice"
            return 1
            ;;
    esac

    save_config

    # Regenerate nginx config
    log_info "Updating nginx configuration..."
    generate_nginx_config

    # Update n8n if installed
    if [[ "${N8N_INSTALLED:-false}" == "true" && -f "$N8N_DIR/docker-compose.yml" ]]; then
        log_info "Updating n8n configuration..."
        cd "$N8N_DIR"
        
        # Update docker-compose file with new settings
        sed -i "s|N8N_EDITOR_BASE_URL=.*|N8N_EDITOR_BASE_URL=http://$SERVER_IP:$NGINX_PORT/n8n/|" docker-compose.yml
        sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=http://$SERVER_IP:$NGINX_PORT/|" docker-compose.yml

        # Restart n8n
        if docker compose version &> /dev/null; then
            docker compose down && docker compose up -d
        else
            docker-compose down && docker-compose up -d
        fi

        # Update nginx route
        write_n8n_route
    fi

    # Reload nginx
    nginx -t && systemctl reload nginx
    log_success "Settings updated successfully"
}

# Refresh all configurations
refresh_config() {
    log_info "Refreshing all configurations..."
    
    generate_nginx_config
    
    if [[ "${N8N_INSTALLED:-false}" == "true" ]]; then
        write_n8n_route
        log_info "Restarting n8n container..."
        cd "$N8N_DIR"
        if docker compose version &> /dev/null; then
            docker compose restart
        else
            docker-compose restart
        fi
    fi

    nginx -t && systemctl reload nginx
    log_success "All configurations refreshed successfully"
}

# Docker status check
docker_status() {
    echo "=== Docker Status ==="
    if check_docker; then
        echo -e "${GREEN}✓ Docker: Installed and Running${NC}"
        docker --version
        docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "Docker Compose: Not found"
        echo ""

        echo "=== Running Containers ==="
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No containers running"
        echo ""

        echo "=== All Containers (including stopped) ==="
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" || echo "No containers found"
        echo ""

        echo "=== n8n Volumes ==="
        docker volume ls | grep n8n || echo "No n8n volumes found"
        echo ""

        echo "=== All Volumes ==="
        docker volume ls --format "table {{.Name}}\t{{.Driver}}" || echo "No volumes found"
    else
        echo -e "${RED}✗ Docker: Not installed or not running${NC}"
    fi
}

# List all Docker containers
list_containers() {
    if ! check_docker; then
        log_error "Docker not available"
        return 1
    fi

    echo "=== All Docker Containers ==="
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
}

# Stop and remove n8n container
remove_n8n_container() {
    if ! check_docker; then
        log_error "Docker not available"
        return 1
    fi

    if ! docker ps -a --format "{{.Names}}" | grep -q "^n8n$"; then
        log_warning "n8n container not found"
        return 1
    fi

    log_warning "This will stop and remove the n8n container."
    read -p "Continue? (y/n): " confirm
    [[ "$confirm" != "y" ]] && log_info "Operation cancelled." && return

    log_info "Stopping n8n container..."
    docker stop n8n 2>/dev/null || true

    log_info "Removing n8n container..."
    if docker rm n8n; then
        log_success "n8n container removed"
    else
        log_error "Failed to remove n8n container"
        return 1
    fi
}

# Remove n8n volumes
remove_n8n_volumes() {
    if ! check_docker; then
        log_error "Docker not available"
        return 1
    fi

    echo "=== n8n Volumes ==="
    docker volume ls | grep n8n || {
        log_warning "No n8n volumes found"
        return 1
    }

    echo ""
    log_warning "This will DELETE ALL n8n data including workflows, credentials, and settings!"
    read -p "Are you sure you want to remove n8n volumes? (yes/no): " confirm
    [[ "$confirm" != "yes" ]] && log_info "Operation cancelled." && return

    log_info "Removing n8n volumes..."

    # Stop container first if running
    docker stop n8n 2>/dev/null || true
    docker rm n8n 2>/dev/null || true

    # Remove volumes
    local removed=0
    for volume in $(docker volume ls -q | grep n8n); do
        if docker volume rm "$volume"; then
            log_success "Removed volume: $volume"
            ((removed++))
        else
            log_error "Failed to remove volume: $volume"
        fi
    done

    if [[ $removed -gt 0 ]]; then
        log_success "Removed $removed n8n volume(s)"
    else
        log_warning "No volumes were removed"
    fi
}

# Clean all Docker resources
docker_cleanup() {
    if ! check_docker; then
        log_error "Docker not available"
        return 1
    fi

    echo "=== Docker Cleanup Options ==="
    echo "1) Remove stopped containers only"
    echo "2) Remove unused volumes"
    echo "3) Remove unused images"
    echo "4) Full cleanup (stopped containers + unused volumes + images)"
    echo "5) Remove ALL containers and volumes (DANGEROUS)"
    echo "6) Cancel"
    echo ""
    read -p "Select option (1-6): " cleanup_choice

    case $cleanup_choice in
        1)
            log_info "Removing stopped containers..."
            docker container prune -f && log_success "Stopped containers removed"
            ;;
        2)
            log_info "Removing unused volumes..."
            docker volume prune -f && log_success "Unused volumes removed"
            ;;
        3)
            log_info "Removing unused images..."
            docker image prune -a -f && log_success "Unused images removed"
            ;;
        4)
            log_warning "This will remove all stopped containers, unused volumes, and images"
            read -p "Continue? (y/n): " confirm
            if [[ "$confirm" == "y" ]]; then
                docker system prune -a --volumes -f && log_success "Docker cleanup completed"
            fi
            ;;
        5)
            log_error "WARNING: This will remove ALL containers and volumes!"
            read -p "Type 'DELETE EVERYTHING' to confirm: " confirm
            if [[ "$confirm" == "DELETE EVERYTHING" ]]; then
                docker stop $(docker ps -aq) 2>/dev/null || true
                docker rm $(docker ps -aq) 2>/dev/null || true
                docker volume rm $(docker volume ls -q) 2>/dev/null || true
                log_success "All containers and volumes removed"
            else
                log_info "Operation cancelled"
            fi
            ;;
        6)
            log_info "Operation cancelled"
            ;;
        *)
            log_error "Invalid option"
            ;;
    esac
}

# Manage n8n container
manage_n8n_container() {
    if ! check_docker; then
        log_error "Docker not available"
        return 1
    fi

    echo "=== n8n Container Management ==="

    # Check if container exists
    if docker ps -a --format "{{.Names}}" | grep -q "^n8n$"; then
        local status=$(docker inspect -f '{{.State.Status}}' n8n)
        echo "n8n Container Status: $status"
        echo ""

        echo "1) Start n8n container"
        echo "2) Stop n8n container"
        echo "3) Restart n8n container"
        echo "4) View n8n logs (live)"
        echo "5) View n8n logs (last 50 lines)"
        echo "6) Remove n8n container"
        echo "7) Remove n8n container AND volumes"
        echo "8) Shell access to n8n container"
        echo "9) Back to menu"
        echo ""
        read -p "Select option (1-9): " n8n_choice

        case $n8n_choice in
            1)
                docker start n8n && log_success "n8n container started"
                ;;
            2)
                docker stop n8n && log_success "n8n container stopped"
                ;;
            3)
                docker restart n8n && log_success "n8n container restarted"
                ;;
            4)
                log_info "Showing live logs (Ctrl+C to exit)..."
                docker logs -f n8n
                ;;
            5)
                docker logs --tail 50 n8n
                ;;
            6)
                remove_n8n_container
                ;;
            7)
                remove_n8n_container
                remove_n8n_volumes
                ;;
            8)
                log_info "Entering n8n container shell..."
                docker exec -it n8n /bin/sh || docker exec -it n8n /bin/bash
                ;;
            9)
                return
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    else
        log_warning "n8n container not found"
        echo ""
        echo "Would you like to install n8n?"
        read -p "(y/n): " install_choice
        [[ "$install_choice" == "y" ]] && install_n8n
    fi
}

# Start services (Docker and nginx)
start_services() {
    echo "=== Start/Enable Services ==="
    echo ""

    local needs_restart=false

    # Check Docker
    if ! check_docker; then
        if command -v docker &> /dev/null; then
            echo -e "${YELLOW}Docker is installed but not running${NC}"
            read -p "Start Docker? (y/n): " start_docker_choice
            if [[ "$start_docker_choice" == "y" ]]; then
                if start_docker; then
                    needs_restart=true
                fi
            fi
        else
            echo -e "${RED}Docker is not installed${NC}"
            read -p "Install Docker now? (y/n): " install_docker_choice
            if [[ "$install_docker_choice" == "y" ]]; then
                install_docker
                needs_restart=true
            fi
        fi
    else
        echo -e "${GREEN}Docker is already running${NC}"
    fi

    echo ""

    # Check nginx
    if ! check_nginx; then
        if command -v nginx &> /dev/null; then
            echo -e "${YELLOW}nginx is installed but not running${NC}"
            read -p "Start nginx? (y/n): " start_nginx_choice
            if [[ "$start_nginx_choice" == "y" ]]; then
                if start_nginx; then
                    needs_restart=true
                fi
            fi
        else
            echo -e "${RED}nginx is not installed${NC}"
            read -p "Install nginx now? (y/n): " install_nginx_choice
            if [[ "$install_nginx_choice" == "y" ]]; then
                install_nginx
                needs_restart=true
            fi
        fi
    else
        echo -e "${GREEN}nginx is already running${NC}"
    fi

    echo ""

    # Check n8n if Docker is running
    if check_docker; then
        if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^n8n$"; then
            if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^n8n$"; then
                echo -e "${YELLOW}n8n container exists but is not running${NC}"
                read -p "Start n8n container? (y/n): " start_n8n_choice
                if [[ "$start_n8n_choice" == "y" ]]; then
                    docker start n8n && log_success "n8n container started"
                fi
            else
                echo -e "${GREEN}n8n is already running${NC}"
            fi
        fi
    fi

    echo ""
    if [[ "$needs_restart" == "true" ]]; then
        log_success "Services have been started"
    fi
}

# System status overview
system_status() {
    echo "=== System Status Overview ==="

    # Docker status
    if check_docker; then
        echo -e "Docker: ${GREEN}✓ Running${NC}"
    else
        if command -v docker &> /dev/null; then
            echo -e "Docker: ${YELLOW}⚠ Installed but not running${NC}"
        else
            echo -e "Docker: ${RED}✗ Not Installed${NC}"
        fi
    fi

    # nginx status
    if check_nginx; then
        echo -e "nginx:  ${GREEN}✓ Running${NC}"
    else
        if command -v nginx &> /dev/null; then
            echo -e "nginx:  ${YELLOW}⚠ Installed but not running${NC}"
        else
            echo -e "nginx:  ${RED}✗ Not Installed${NC}"
        fi
    fi

    # n8n status
    if check_docker && docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^n8n$"; then
        echo -e "n8n:    ${GREEN}✓ Running${NC}"
    elif check_docker && docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^n8n$"; then
        echo -e "n8n:    ${YELLOW}⚠ Container exists but not running${NC}"
    elif [[ "$N8N_INSTALLED" == "true" ]]; then
        echo -e "n8n:    ${YELLOW}⚠ Marked as installed${NC}"
    else
        echo -e "n8n:    ${RED}✗ Not Installed${NC}"
    fi
    
    echo ""
    echo "=== Access Information ==="
    echo "Nginx Router: http://$SERVER_IP:$NGINX_PORT"
    if [[ "$N8N_INSTALLED" == "true" ]]; then
        # Find the configured n8n path from PORT_MAPPINGS
        local n8n_path=""
        for path in "${!PORT_MAPPINGS[@]}"; do
            if [[ "${PORT_MAPPINGS[$path]}" == "5678" ]]; then
                n8n_path="$path"
                break
            fi
        done

        if [[ -n "$n8n_path" ]]; then
            echo "n8n External: http://$SERVER_IP:$NGINX_PORT${n8n_path}"
            echo "n8n Local:    http://127.0.0.1:5678/"
        else
            echo "n8n:          Status unknown (check configuration)"
        fi
    fi
}

# Main menu
menu() {
    while true; do
        clear
        echo -e "${BLUE}"
        echo "╔══════════════════════════════════════════╗"
        echo "║           N8S - Manager v4.0            ║"
        echo "║    nginx + Docker + n8n Super Script    ║"
        echo "╚══════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
        
        # Quick status
        system_status
        
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║               Main Menu                  ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        echo "  === Installation & Setup ==="
        echo "  1)  Install n8n (Full Setup)"
        echo "  2)  Install Docker Only"
        echo "  3)  Install nginx Only"
        echo "  4)  Reinstall n8n"
        echo "  5)  Start/Enable Services"
        echo ""
        echo "  === Configuration ==="
        echo "  6)  Add Custom Route"
        echo "  7)  List Routes & Status"
        echo "  8)  Remove Route"
        echo "  9)  Change Settings"
        echo "  10) Refresh All Configs"
        echo ""
        echo "  === Docker Management ==="
        echo "  11) Docker Status & Info"
        echo "  12) List All Containers"
        echo "  13) Manage n8n Container"
        echo "  14) Remove n8n Volumes"
        echo "  15) Docker Cleanup"
        echo ""
        echo "  === System ==="
        echo "  16) System Status"
        echo "  17) Update Script"
        echo ""
        echo "  === Troubleshooting/Repair ==="
        echo "  18) Reinstall Docker"
        echo "  19) Reinstall nginx"
        echo ""
        echo "  20) Exit"
        echo ""
        read -p "Select option: " choice

        case $choice in
            1) install_n8n; read -p "Press enter to continue... " ;;
            2) install_docker; read -p "Press enter to continue... " ;;
            3) install_nginx; read -p "Press enter to continue... " ;;
            4) reinstall_n8n; read -p "Press enter to continue... " ;;
            5) start_services; read -p "Press enter to continue... " ;;
            6) add_route; read -p "Press enter to continue... " ;;
            7) list_routes; read -p "Press enter to continue... " ;;
            8) remove_route; read -p "Press enter to continue... " ;;
            9) change_settings; read -p "Press enter to continue... " ;;
            10) refresh_config; read -p "Press enter to continue... " ;;
            11) docker_status; read -p "Press enter to continue... " ;;
            12) list_containers; read -p "Press enter to continue... " ;;
            13) manage_n8n_container; read -p "Press enter to continue... " ;;
            14) remove_n8n_volumes; read -p "Press enter to continue... " ;;
            15) docker_cleanup; read -p "Press enter to continue... " ;;
            16) system_status; read -p "Press enter to continue... " ;;
            17) update_script ;;
            18) reinstall_docker; read -p "Press enter to continue... " ;;
            19) reinstall_nginx; read -p "Press enter to continue... " ;;
            20) log_info "Goodbye!"; exit 0 ;;
            *) log_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# Handle command line arguments
case "${1:-}" in
    "-update"|"update")
        INTERACTIVE_MODE=false
        update_script
        ;;
    "-status"|"status")
        INTERACTIVE_MODE=false
        load_config
        system_status
        ;;
    "-install-docker")
        INTERACTIVE_MODE=false
        install_docker
        ;;
    "-install-nginx")
        INTERACTIVE_MODE=false
        install_nginx
        ;;
    "-install-n8n")
        INTERACTIVE_MODE=false
        load_config
        install_n8n
        ;;
    "-list-containers")
        INTERACTIVE_MODE=false
        load_config
        list_containers
        ;;
    "-manage-n8n")
        INTERACTIVE_MODE=false
        load_config
        manage_n8n_container
        ;;
    "-docker-cleanup")
        INTERACTIVE_MODE=false
        load_config
        docker_cleanup
        ;;
    "-docker-status")
        INTERACTIVE_MODE=false
        load_config
        docker_status
        ;;
    "-start-services"|"start-services")
        INTERACTIVE_MODE=false
        load_config
        start_services
        ;;
    "-reinstall-docker")
        load_config
        reinstall_docker
        ;;
    "-reinstall-nginx")
        load_config
        reinstall_nginx
        ;;
    "-help"|"help"|"-h")
        echo "N8S Manager - nginx + Docker + n8n Super Script"
        echo ""
        echo "Usage: $0 [option]"
        echo ""
        echo "Installation Options:"
        echo "  -install-docker        Install Docker only"
        echo "  -install-nginx         Install nginx only"
        echo "  -install-n8n           Install n8n with full setup"
        echo "  -start-services        Start/enable Docker, nginx, and n8n services"
        echo ""
        echo "Status & Information:"
        echo "  status, -status        Show system status overview"
        echo "  -docker-status         Show detailed Docker status"
        echo "  -list-containers       List all Docker containers"
        echo ""
        echo "Docker Management:"
        echo "  -manage-n8n            Manage n8n container (start/stop/logs/etc)"
        echo "  -docker-cleanup        Clean up Docker resources"
        echo ""
        echo "Troubleshooting/Repair:"
        echo "  -reinstall-docker      Completely remove and reinstall Docker"
        echo "  -reinstall-nginx       Completely remove and reinstall nginx"
        echo ""
        echo "System:"
        echo "  update, -update        Update script from repository"
        echo "  help, -help, -h        Show this help"
        echo ""
        echo "Running without options starts the interactive menu"
        echo ""
        exit 0
        ;;
esac

# Main execution
load_config

# Check if running with sudo/root
check_root

# Start menu if no command line options
if [[ $# -eq 0 ]]; then
    menu
fi
