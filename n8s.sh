#!/bin/bash

CONFIG_FILE="/etc/n8s/config.env"
ROUTES_DIR="/etc/nginx/routes-8443"
SCRIPT_PATH="/usr/local/bin/n8s"
REPO_URL="https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/n8s.sh"
N8N_DIR="$HOME/rfp/n8n"

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        NGINX_PORT=8443
        SERVER_IP=$(curl -s ifconfig.me || echo "localhost")
        N8N_INSTALLED=false
        DOCKER_INSTALLED=false
        declare -A PORT_MAPPINGS
    fi
}

save_config() {
    mkdir -p /etc/n8s
    cat > "$CONFIG_FILE" << EOF
NGINX_PORT=$NGINX_PORT
SERVER_IP=$SERVER_IP
N8N_INSTALLED=$N8N_INSTALLED
DOCKER_INSTALLED=$DOCKER_INSTALLED
N8N_DIR=$N8N_DIR
$(declare -p PORT_MAPPINGS 2>/dev/null || echo "declare -A PORT_MAPPINGS=()")
EOF
}

update_script() {
    echo "Updating n8s from repository..."
    curl -fsSL "$REPO_URL" -o /tmp/n8s_new.sh
    if [[ $? -eq 0 ]]; then
        chmod +x /tmp/n8s_new.sh
        mv /tmp/n8s_new.sh "$SCRIPT_PATH"
        echo "Update completed successfully"
        exit 0
    else
        echo "Update failed"
        exit 1
    fi
}

install_docker() {
    echo "Installing Docker and Docker Compose..."
    
    apt update
    apt install -y ca-certificates curl gnupg lsb-release
    
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    systemctl enable --now docker
    
    usermod -aG docker $USER
    
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        echo "Docker and Docker Compose installed successfully"
        DOCKER_INSTALLED=true
        save_config
        return 0
    else
        echo "Docker installation failed, trying alternative method..."
        apt install -y docker.io docker-compose
        systemctl enable --now docker
        
        if command -v docker &> /dev/null; then
            DOCKER_INSTALLED=true
            save_config
            echo "Docker installed via apt"
            return 0
        else
            echo "Docker installation failed"
            return 1
        fi
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker not found"
        return 1
    fi
    
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose not found"
        return 1
    fi
    
    return 0
}

install_nginx() {
    if ! command -v nginx &> /dev/null; then
        echo "Installing nginx..."
        apt update
        apt install -y nginx
        systemctl enable --now nginx
    fi
    
    mkdir -p "$ROUTES_DIR"
    
    cat > /etc/nginx/sites-available/8443-router.conf << 'NGXEOF'
server {
    listen NGINX_PORT_PLACEHOLDER default_server;
    listen [::]:NGINX_PORT_PLACEHOLDER default_server;
    server_name _;
    location = / {
        return 200 'nginx router is alive\n';
        add_header Content-Type text/plain;
    }
    include /etc/nginx/routes-8443/*.conf;
}
NGXEOF
    
    sed -i "s/NGINX_PORT_PLACEHOLDER/$NGINX_PORT/g" /etc/nginx/sites-available/8443-router.conf
    
    ln -sf /etc/nginx/sites-available/8443-router.conf /etc/nginx/sites-enabled/8443-router.conf
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl reload nginx
}

install_n8n() {
    if ! check_docker; then
        echo "Docker not installed. Please install Docker first (Option 8)"
        return 1
    fi
    
    echo "Setting up n8n..."
    
    if [[ ! -d "$N8N_DIR" ]]; then
        echo "Creating directory: $N8N_DIR"
        mkdir -p "$N8N_DIR"
    else
        echo "Directory exists: $N8N_DIR"
    fi
    
    if [[ -f "$N8N_DIR/docker-compose.yml" ]]; then
        read -p "docker-compose.yml exists. Overwrite? (y/n): " overwrite
        if [[ "$overwrite" != "y" ]]; then
            echo "Skipping docker-compose.yml creation"
            return 1
        fi
    fi
    
    docker volume create n8n_data
    
    cat > "$N8N_DIR/docker-compose.yml" << DCEOF
version: '3.8'
services:
  n8n:
    image: docker.io/n8nio/n8n:latest
    container_name: n8n
    restart: always
    network_mode: host
    environment:
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - N8N_HOST=0.0.0.0
      - N8N_PATH=/n8n/
      - N8N_EDITOR_BASE_URL=http://$SERVER_IP:$NGINX_PORT/n8n/
      - WEBHOOK_URL=http://$SERVER_IP:$NGINX_PORT/
      - N8N_ALLOWED_ORIGINS=*
      - N8N_SECURE_COOKIE=false
      - N8N_PUSH_BACKEND=websocket
      - N8N_PROXY_HOPS=1
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - DB_SQLITE_POOL_SIZE=3
    volumes:
      - n8n_data:/home/node/.n8n
volumes:
  n8n_data:
    external: true
DCEOF
    
    echo "Starting n8n container..."
    cd "$N8N_DIR"
    docker compose up -d
    
    cat > "$ROUTES_DIR/n8n.conf" << 'N8NEOF'
location /n8n/ {
    proxy_pass http://127.0.0.1:5678/n8n/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Origin "http://SERVER_IP_PLACEHOLDER";
}
location = /n8n {
    return 301 /n8n/;
}
N8NEOF
    
    sed -i "s/SERVER_IP_PLACEHOLDER/$SERVER_IP/g" "$ROUTES_DIR/n8n.conf"
    
    nginx -t && systemctl reload nginx
    
    N8N_INSTALLED=true
    PORT_MAPPINGS["/n8n/"]="5678"
    save_config
    
    echo "n8n installed at http://$SERVER_IP:$NGINX_PORT/n8n/"
    echo "docker-compose.yml location: $N8N_DIR/docker-compose.yml"
}

add_route() {
    read -p "Enter nginx path (e.g., /api/): " path
    read -p "Enter internal port: " port
    read -p "Route name (alphanumeric): " name
    
    [[ ! "$path" =~ ^/ ]] && path="/$path"
    [[ ! "$path" =~ /$ ]] && path="$path/"
    
    cat > "$ROUTES_DIR/${name}.conf" << RTEOF
location $path {
    proxy_pass http://127.0.0.1:$port/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
RTEOF
    
    nginx -t && systemctl reload nginx
    
    PORT_MAPPINGS["$path"]="$port"
    save_config
    
    echo "Route added: http://$SERVER_IP:$NGINX_PORT$path -> localhost:$port"
}

list_routes() {
    echo "=== Current Routes ==="
    echo "Nginx Port: $NGINX_PORT"
    echo "Server IP: $SERVER_IP"
    echo "Docker Status: $DOCKER_INSTALLED"
    echo "n8n Status: $N8N_INSTALLED"
    echo "n8n Directory: $N8N_DIR"
    echo ""
    for path in "${!PORT_MAPPINGS[@]}"; do
        echo "http://$SERVER_IP:$NGINX_PORT$path -> localhost:${PORT_MAPPINGS[$path]}"
    done
}

remove_route() {
    read -p "Enter path to remove (e.g., /api/): " path
    read -p "Enter route name: " name
    
    rm -f "$ROUTES_DIR/${name}.conf"
    nginx -t && systemctl reload nginx
    
    unset PORT_MAPPINGS["$path"]
    save_config
    
    echo "Route removed"
}

change_settings() {
    read -p "Enter new nginx port [$NGINX_PORT]: " new_port
    [[ -n "$new_port" ]] && NGINX_PORT=$new_port
    
    read -p "Enter server IP [$SERVER_IP]: " new_ip
    [[ -n "$new_ip" ]] && SERVER_IP=$new_ip
    
    read -p "Enter n8n directory [$N8N_DIR]: " new_dir
    [[ -n "$new_dir" ]] && N8N_DIR=$new_dir
    
    save_config
    
    sed -i "s/listen [0-9]\+/listen $NGINX_PORT/g" /etc/nginx/sites-available/8443-router.conf
    
    if [[ "$N8N_INSTALLED" == "true" && -f "$N8N_DIR/docker-compose.yml" ]]; then
        cd "$N8N_DIR"
        sed -i "s|N8N_EDITOR_BASE_URL=.*|N8N_EDITOR_BASE_URL=http://$SERVER_IP:$NGINX_PORT/n8n/|" docker-compose.yml
        sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=http://$SERVER_IP:$NGINX_PORT/|" docker-compose.yml
        docker compose down
        docker compose up -d
        
        sed -i "s|Origin \"http://.*\"|Origin \"http://$SERVER_IP\"|" "$ROUTES_DIR/n8n.conf"
    fi
    
    nginx -t && systemctl reload nginx
    echo "Settings updated"
}

docker_status() {
    echo "=== Docker Status ==="
    if check_docker; then
        echo "Docker: Installed"
        docker --version
        docker compose version 2>/dev/null || docker-compose --version
        echo ""
        echo "Running containers:"
        docker ps
    else
        echo "Docker: Not installed"
    fi
}

menu() {
    while true; do
        clear
        echo "╔════════════════════════════════════╗"
        echo "║      N8S - Nginx Manager v2.0     ║"
        echo "╚════════════════════════════════════╝"
        echo ""
        echo "  1) Install n8n"
        echo "  2) Add Route"
        echo "  3) List Routes"
        echo "  4) Remove Route"
        echo "  5) Change Settings"
        echo "  6) Update Script"
        echo "  7) Docker Status"
        echo "  8) Install Docker"
        echo "  9) Exit"
        echo ""
        read -p "Select option: " choice
        
        case $choice in
            1) install_nginx && install_n8n; read -p "Press enter..." ;;
            2) add_route; read -p "Press enter..." ;;
            3) list_routes; read -p "Press enter..." ;;
            4) remove_route; read -p "Press enter..." ;;
            5) change_settings; read -p "Press enter..." ;;
            6) update_script ;;
            7) docker_status; read -p "Press enter..." ;;
            8) install_docker; read -p "Press enter..." ;;
            9) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

if [[ "$1" == "-update" ]] || [[ "$1" == "update" ]]; then
    update_script
fi

load_config
menu
