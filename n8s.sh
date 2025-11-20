#!/bin/bash

set -euo pipefail

CONFIG_FILE="/etc/n8s/config.env"
SCRIPT_PATH="/usr/local/bin/n8s"
REPO_URL="https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/n8s.sh"

N8N_DIR="${HOME}/rfp/n8n"
NGINX_CONF="/etc/nginx/sites-available/n8s-router.conf"
ROUTES_DIR="/etc/nginx/routes-n8s"
NGINX_PORT_DEFAULT=1440

declare -gA PORT_MAPPINGS || true

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        echo "No existing config found. Let's set things up."

        read -p "Enter nginx port to listen on [${NGINX_PORT_DEFAULT}]: " input_port
        if [[ -n "${input_port:-}" ]]; then
            NGINX_PORT="$input_port"
        else
            NGINX_PORT="$NGINX_PORT_DEFAULT"
        fi

        read -p "Enter n8n directory [${N8N_DIR}]: " input_dir
        if [[ -n "${input_dir:-}" ]]; then
            N8N_DIR="$input_dir"
        fi

        SERVER_IP=$(curl -s ifconfig.me || echo "localhost")
        N8N_INSTALLED=false
        DOCKER_INSTALLED=false
        declare -gA PORT_MAPPINGS

        save_config
    fi

    : "${NGINX_PORT:=$NGINX_PORT_DEFAULT}"
    : "${SERVER_IP:=$(curl -s ifconfig.me || echo "localhost")}"
    : "${N8N_DIR:=${HOME}/rfp/n8n}"
    : "${ROUTES_DIR:=/etc/nginx/routes-n8s}"
    : "${NGINX_CONF:=/etc/nginx/sites-available/n8s-router.conf}"
}

save_config() {
    mkdir -p /etc/n8s
    {
        echo "NGINX_PORT=$NGINX_PORT"
        echo "SERVER_IP='$SERVER_IP'"
        echo "N8N_INSTALLED=$N8N_INSTALLED"
        echo "DOCKER_INSTALLED=$DOCKER_INSTALLED"
        echo "N8N_DIR='$N8N_DIR'"
        echo "ROUTES_DIR='$ROUTES_DIR'"
        echo "NGINX_CONF='$NGINX_CONF'"
        if [[ ${#PORT_MAPPINGS[@]} -gt 0 ]]; then
            echo "declare -gA PORT_MAPPINGS=("
            for key in "${!PORT_MAPPINGS[@]}"; do
                echo "  ['$key']='${PORT_MAPPINGS[$key]}'"
            done
            echo ")"
        else
            echo "declare -gA PORT_MAPPINGS=()"
        fi
    } > "$CONFIG_FILE"
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

    export DEBIAN_FRONTEND=noninteractive

    apt update
    apt install -y ca-certificates curl gnupg lsb-release

    mkdir -p /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    fi

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update

    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | tee /tmp/docker_install.log

    if grep -q "Errors were encountered while processing" /tmp/docker_install.log 2>/dev/null; then
        echo "Warning: Some package errors occurred, attempting to fix..."
        dpkg --configure -a || true
        apt --fix-broken install -y || true
    fi

    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true

    usermod -aG docker "$USER" 2>/dev/null || true

    if command -v docker &> /dev/null; then
        if docker compose version &> /dev/null 2>&1; then
            echo "Docker and Docker Compose installed successfully"
            DOCKER_INSTALLED=true
            save_config
            return 0
        elif command -v docker-compose &> /dev/null; then
            echo "Docker installed with docker-compose"
            DOCKER_INSTALLED=true
            save_config
            return 0
        else
            echo "Installing standalone docker-compose..."
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            DOCKER_INSTALLED=true
            save_config
            return 0
        fi
    else
        echo "Docker installation failed, trying alternative method..."
        apt install -y docker.io
        systemctl enable --now docker || true

        if command -v docker &> /dev/null; then
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
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
        return 1
    fi

    if ! systemctl is-active --quiet docker; then
        systemctl start docker 2>/dev/null || true
        sleep 2
    fi

    if ! docker compose version &> /dev/null 2>&1 && ! command -v docker-compose &> /dev/null; then
        return 1
    fi

    return 0
}

patch_nginx_conf() {
    return 0
}

generate_nginx_config() {
    mkdir -p "$ROUTES_DIR"

    rm -f /etc/nginx/sites-available/8443-router.conf 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/8443-router.conf 2>/dev/null || true
    rmdir /etc/nginx/routes-8443 2>/dev/null || true

    patch_nginx_conf

    cat > "$NGINX_CONF" << 'NGXEOF'
server {
    listen NGINX_PORT_PLACEHOLDER default_server;
    listen [::]:NGINX_PORT_PLACEHOLDER default_server;
    server_name _;
    client_max_body_size 100M;

    location = / {
        return 200 'nginx router is alive\n';
        add_header Content-Type text/plain;
    }

    include ROUTES_DIR_PLACEHOLDER/*.conf;
}
NGXEOF

    sed -i "s/NGINX_PORT_PLACEHOLDER/$NGINX_PORT/g" "$NGINX_CONF"
    sed -i "s|ROUTES_DIR_PLACEHOLDER|$ROUTES_DIR|g" "$NGINX_CONF"

    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/n8s-router.conf
    rm -f /etc/nginx/sites-enabled/default || true

    nginx -t && systemctl reload nginx
}

install_nginx() {
    if ! command -v nginx &> /dev/null; then
        echo "Installing nginx..."
        apt update
        apt install -y nginx
        systemctl enable --now nginx
    fi

    generate_nginx_config
}

write_n8n_route() {
    mkdir -p "$ROUTES_DIR"
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
    proxy_set_header Origin "$scheme://$host";
    proxy_buffering off;
    proxy_request_buffering off;
}
location = /n8n {
    return 301 /n8n/;
}
N8NEOF
}

install_n8n() {
    if ! check_docker; then
        echo "Docker not installed or not running. Please install Docker first (Option 8)"
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
        read -p "docker-compose.yml exists in $N8N_DIR. Overwrite? (y/n): " overwrite
        if [[ "$overwrite" != "y" ]]; then
            echo "Skipping docker-compose.yml creation"
            return 1
        fi
    fi

    docker volume create n8n_data 2>/dev/null || true

    cat > "$N8N_DIR/docker-compose.yml" << DCEOF
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

    if docker compose version &> /dev/null 2>&1; then
        docker compose up -d
    else
        docker-compose up -d
    fi

    write_n8n_route

    nginx -t && systemctl reload nginx

    N8N_INSTALLED=true
    PORT_MAPPINGS['/n8n/']=5678
    save_config

    echo ""
    echo "========================================="
    echo "n8n installed successfully!"
    echo "URL: http://$SERVER_IP:$NGINX_PORT/n8n/"
    echo "Config: $N8N_DIR/docker-compose.yml"
    echo "========================================="
    echo ""
}

reinstall_n8n() {
    if ! check_docker; then
        echo "Docker not installed or not running. Use option 8 first."
        return 1
    fi

    if [[ "${N8N_INSTALLED:-false}" != "true" || ! -f "$N8N_DIR/docker-compose.yml" ]]; then
        echo "n8n does not appear to be installed via this script."
        echo "Running a fresh install instead..."
        install_nginx
        install_n8n
        return
    fi

    echo "This will stop and recreate the n8n container."
    read -p "Continue? (y/n): " confirm
    [[ "$confirm" != "y" ]] && echo "Reinstall cancelled." && return

    cd "$N8N_DIR" || {
        echo "Cannot cd into $N8N_DIR, aborting."
        return 1
    }

    echo "Stopping existing n8n container..."
    if docker compose version &> /dev/null 2>&1; then
        docker compose down
    else
        docker-compose down
    fi

    read -p "Remove existing docker volume 'n8n_data'? This will wipe all n8n data. (y/n): " wipe
    if [[ "$wipe" == "y" ]]; then
        echo "Removing volume n8n_data..."
        docker volume rm n8n_data 2>/dev/null || true
    fi

    N8N_INSTALLED=false
    save_config

    echo "Reinstalling n8n..."
    install_n8n
}

add_route() {
    read -p "Enter nginx path (e.g., /api/): " path
    read -p "Enter internal port: " port
    read -p "Route name (alphanumeric): " name

    [[ ! "$path" =~ ^/ ]] && path="/$path"
    [[ ! "$path" =~ /$ ]] && path="$path/"

    mkdir -p "$ROUTES_DIR"

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
    echo "Nginx Port : $NGINX_PORT"
    echo "Server IP  : $SERVER_IP"
    echo "Docker     : $DOCKER_INSTALLED"
    echo "n8n        : $N8N_INSTALLED"
    echo "n8n Dir    : $N8N_DIR"
    echo "Routes Dir : $ROUTES_DIR"
    echo ""
    if [[ ${#PORT_MAPPINGS[@]} -eq 0 ]]; then
        echo "No routes configured"
    else
        for path in "${!PORT_MAPPINGS[@]}"; do
            echo "http://$SERVER_IP:$NGINX_PORT$path -> localhost:${PORT_MAPPINGS[$path]}"
        done
    fi
}

remove_route() {
    list_routes
    echo ""
    read -p "Enter route name to remove (conf name without .conf): " name

    if [[ -f "$ROUTES_DIR/${name}.conf" ]]; then
        rm -f "$ROUTES_DIR/${name}.conf"
        nginx -t && systemctl reload nginx

        for path in "${!PORT_MAPPINGS[@]}"; do
            if [[ "$path" == *"$name"* ]]; then
                unset 'PORT_MAPPINGS[$path]'
                break
            fi
        done

        save_config
        echo "Route removed"
    else
        echo "Route not found"
    fi
}

change_settings() {
    read -p "Enter new nginx port [$NGINX_PORT]: " new_port
    [[ -n "${new_port:-}" ]] && NGINX_PORT="$new_port"

    read -p "Enter server IP [$SERVER_IP]: " new_ip
    [[ -n "${new_ip:-}" ]] && SERVER_IP="$new_ip"

    read -p "Enter n8n directory [$N8N_DIR]: " new_dir
    [[ -n "${new_dir:-}" ]] && N8N_DIR="$new_dir"

    save_config

    echo "Regenerating nginx config for new port..."
    generate_nginx_config

    if [[ "${N8N_INSTALLED:-false}" == "true" && -f "$N8N_DIR/docker-compose.yml" ]]; then
        cd "$N8N_DIR"
        sed -i "s|N8N_EDITOR_BASE_URL=.*|N8N_EDITOR_BASE_URL=http://$SERVER_IP:$NGINX_PORT/n8n/|" docker-compose.yml
        sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=http://$SERVER_IP:$NGINX_PORT/|" docker-compose.yml

        if docker compose version &> /dev/null 2>&1; then
            docker compose down
            docker compose up -d
        else
            docker-compose down
            docker-compose up -d
        fi
    fi

    nginx -t && systemctl reload nginx
    echo "Settings updated"
}

refresh_config() {
    echo "Refreshing nginx and n8n configs using current settings..."
    generate_nginx_config
    write_n8n_route

    nginx -t && systemctl reload nginx

    if [[ "${N8N_INSTALLED:-false}" == "true" && -f "$N8N_DIR/docker-compose.yml" ]]; then
        echo "Restarting n8n container to apply any config changes..."
        cd "$N8N_DIR"
        if docker compose version &> /dev/null 2>&1; then
            docker compose down
            docker compose up -d
        else
            docker-compose down
            docker-compose up -d
        fi
    fi

    echo "Config refresh complete."
}

docker_status() {
    echo "=== Docker Status ==="
    if check_docker; then
        echo "Docker: Installed and Running"
        docker --version
        docker compose version 2>/dev/null || docker-compose --version 2>/dev/null
        echo ""
        echo "Running containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo "Docker volumes (n8n-related):"
        docker volume ls | grep n8n || echo "No n8n volumes"
    else
        echo "Docker: Not installed or not running"
    fi
}

menu() {
    while true; do
        clear
        echo "╔════════════════════════════════════╗"
        echo "║      N8S - Nginx Manager v3.3     ║"
        echo "╚════════════════════════════════════╝"
        echo ""
        echo "  1) Install n8n"
        echo "  2) Add Route"
        echo "  3) List Routes"
        echo "  4) Remove Route"
        echo "  5) Change Settings (port/IP/dir)"
        echo "  6) Update Script"
        echo "  7) Docker Status"
        echo "  8) Install Docker"
        echo "  9) Exit"
        echo " 10) Reinstall n8n"
        echo " 11) Refresh Config (nginx + n8n)"
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
            10) reinstall_n8n; read -p "Press enter..." ;;
            11) refresh_config; read -p "Press enter..." ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

if [[ "${1:-}" == "-update" || "${1:-}" == "update" ]]; then
    update_script
fi

load_config
menu
