#!/bin/bash

# Docker Management Script (docker-ms)
# Source: https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/docker-ms.sh

set -e

VERSION="1.0.0"
SCRIPT_URL="https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/docker-ms.sh"
INSTALL_PATH="/usr/local/bin/docker-ms"
CONFIG_DIR="/etc/docker-ms"
CONFIG_FILE="$CONFIG_DIR/autostart.conf"
COMPOSE_MAP="$CONFIG_DIR/compose-map.conf"
SERVICE_FILE="/etc/systemd/system/docker-ms-autostart.service"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This operation requires root privileges. Please run with sudo."
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
}

# Initialize config directory
init_config() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        touch "$CONFIG_FILE"
        touch "$COMPOSE_MAP"
    fi
}

# Detect if container is from compose and get compose file path
detect_compose_file() {
    local container_id=$1
    local compose_path=""
    
    # Check for compose project label
    compose_path=$(docker inspect "$container_id" --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null || echo "")
    
    if [[ -n "$compose_path" ]]; then
        echo "$compose_path"
        return 0
    fi
    
    # Check working directory
    local working_dir=$(docker inspect "$container_id" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null || echo "")
    if [[ -n "$working_dir" ]] && [[ -f "$working_dir/docker-compose.yml" ]]; then
        echo "$working_dir/docker-compose.yml"
        return 0
    fi
    
    echo ""
    return 1
}

# Get container type (compose or standalone)
get_container_type() {
    local container_id=$1
    local project=$(docker inspect "$container_id" --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo "")
    
    if [[ -n "$project" ]]; then
        echo "compose"
    else
        echo "standalone"
    fi
}

# List all containers with details
list_containers() {
    check_docker
    
    echo ""
    echo "==================================================================="
    printf "%-15s %-25s %-12s %-15s\n" "CONTAINER ID" "NAME" "STATUS" "TYPE"
    echo "==================================================================="
    
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" | tail -n +2 | while read line; do
        local id=$(echo "$line" | awk '{print $1}')
        local name=$(echo "$line" | awk '{print $2}')
        local status=$(echo "$line" | awk '{print $3}')
        local type=$(get_container_type "$id")
        
        printf "%-15s %-25s %-12s %-15s\n" "$id" "$name" "$status" "$type"
    done
    echo "==================================================================="
    echo ""
}

# Get autostart containers
get_autostart_containers() {
    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE" | grep -v '^#' | grep -v '^$'
    fi
}

# Add container to autostart
add_to_autostart() {
    local container=$1
    init_config
    
    # Check if already exists
    if grep -q "^$container$" "$CONFIG_FILE" 2>/dev/null; then
        print_warning "Container $container is already in autostart list"
        return 1
    fi
    
    # Detect and save compose file if applicable
    local compose_file=$(detect_compose_file "$container")
    if [[ -n "$compose_file" ]]; then
        echo "$container=$compose_file" >> "$COMPOSE_MAP"
        print_info "Detected compose file: $compose_file"
    fi
    
    echo "$container" >> "$CONFIG_FILE"
    print_success "Added $container to autostart"
}

# Remove container from autostart
remove_from_autostart() {
    local container=$1
    init_config
    
    if grep -q "^$container$" "$CONFIG_FILE" 2>/dev/null; then
        sed -i "/^$container$/d" "$CONFIG_FILE"
        sed -i "/^$container=/d" "$COMPOSE_MAP" 2>/dev/null || true
        print_success "Removed $container from autostart"
    else
        print_warning "Container $container not found in autostart list"
    fi
}

# Start autostart containers
start_autostart_containers() {
    check_docker
    init_config
    
    print_info "Starting autostart containers..."
    
    local started=0
    local failed=0
    
    while IFS= read -r container; do
        [[ -z "$container" ]] && continue
        
        # Check if container exists
        if ! docker ps -a --format '{{.Names}}' | grep -q "^$container$"; then
            print_warning "Container $container not found, skipping..."
            ((failed++))
            continue
        fi
        
        # Check if already running
        if docker ps --format '{{.Names}}' | grep -q "^$container$"; then
            print_info "Container $container is already running"
            continue
        fi
        
        # Get compose file if exists
        local compose_file=$(grep "^$container=" "$COMPOSE_MAP" 2>/dev/null | cut -d'=' -f2)
        
        if [[ -n "$compose_file" ]] && [[ -f "$compose_file" ]]; then
            print_info "Starting $container using compose file..."
            if docker-compose -f "$compose_file" up -d "$container" 2>/dev/null; then
                print_success "Started $container (compose)"
                ((started++))
            else
                print_error "Failed to start $container (compose)"
                ((failed++))
            fi
        else
            print_info "Starting $container as standalone container..."
            if docker start "$container" &>/dev/null; then
                print_success "Started $container (standalone)"
                ((started++))
            else
                print_error "Failed to start $container"
                ((failed++))
            fi
        fi
    done < "$CONFIG_FILE"
    
    echo ""
    print_info "Summary: $started started, $failed failed"
}

# Install systemd service
install_service() {
    check_root
    
    print_info "Installing systemd service..."
    
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Docker Management Script - Autostart Containers
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/docker-ms --start-autostart
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable docker-ms-autostart.service
    
    print_success "Systemd service installed and enabled"
    print_info "Containers will now auto-start on boot"
}

# Uninstall systemd service
uninstall_service() {
    check_root
    
    if [[ -f "$SERVICE_FILE" ]]; then
        systemctl disable docker-ms-autostart.service 2>/dev/null || true
        systemctl stop docker-ms-autostart.service 2>/dev/null || true
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        print_success "Systemd service uninstalled"
    else
        print_warning "Service not installed"
    fi
}

# Self-update function
self_update() {
    check_root
    
    print_info "Checking for updates..."
    
    local temp_file=$(mktemp)
    
    if curl -fsSL "$SCRIPT_URL" -o "$temp_file"; then
        if [[ -s "$temp_file" ]]; then
            chmod +x "$temp_file"
            mv "$temp_file" "$INSTALL_PATH"
            print_success "Updated to latest version"
            print_info "Please run the command again"
            exit 0
        else
            print_error "Downloaded file is empty"
            rm -f "$temp_file"
            exit 1
        fi
    else
        print_error "Failed to download update"
        rm -f "$temp_file"
        exit 1
    fi
}

# Install script system-wide
install_script() {
    check_root
    
    if [[ ! -f "$INSTALL_PATH" ]]; then
        cp "$0" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        print_success "Installed to $INSTALL_PATH"
    else
        print_info "Already installed at $INSTALL_PATH"
    fi
    
    init_config
    install_service
    
    print_success "Installation complete!"
    print_info "Use 'docker-ms -i' for interactive menu"
}

# Interactive menu
interactive_menu() {
    check_docker
    
    while true; do
        clear
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║         Docker Management Script - Interactive Menu       ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  1) List all containers"
        echo "  2) Show autostart containers"
        echo "  3) Add container to autostart"
        echo "  4) Remove container from autostart"
        echo "  5) Start autostart containers now"
        echo "  6) Set/Update compose file path for container"
        echo "  7) Install/Reinstall systemd service"
        echo "  8) Uninstall systemd service"
        echo "  9) Update docker-ms script"
        echo "  0) Exit"
        echo ""
        read -p "Select option: " choice
        
        case $choice in
            1)
                list_containers
                read -p "Press Enter to continue..."
                ;;
            2)
                echo ""
                print_info "Autostart containers:"
                echo "─────────────────────────────────────────────────────────"
                get_autostart_containers | while read container; do
                    local compose_file=$(grep "^$container=" "$COMPOSE_MAP" 2>/dev/null | cut -d'=' -f2)
                    if [[ -n "$compose_file" ]]; then
                        echo "  • $container (compose: $compose_file)"
                    else
                        echo "  • $container (standalone)"
                    fi
                done
                [[ ! -s "$CONFIG_FILE" ]] && echo "  (none configured)"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                list_containers
                read -p "Enter container name or ID: " container
                if [[ -n "$container" ]]; then
                    add_to_autostart "$container"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                echo ""
                print_info "Current autostart containers:"
                get_autostart_containers
                echo ""
                read -p "Enter container name to remove: " container
                if [[ -n "$container" ]]; then
                    remove_from_autostart "$container"
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                echo ""
                start_autostart_containers
                read -p "Press Enter to continue..."
                ;;
            6)
                echo ""
                read -p "Enter container name: " container
                read -p "Enter compose file path: " compose_path
                if [[ -n "$container" ]] && [[ -n "$compose_path" ]]; then
                    sed -i "/^$container=/d" "$COMPOSE_MAP" 2>/dev/null || true
                    echo "$container=$compose_path" >> "$COMPOSE_MAP"
                    print_success "Compose path set for $container"
                fi
                read -p "Press Enter to continue..."
                ;;
            7)
                echo ""
                install_service
                read -p "Press Enter to continue..."
                ;;
            8)
                echo ""
                uninstall_service
                read -p "Press Enter to continue..."
                ;;
            9)
                echo ""
                self_update
                ;;
            0)
                echo ""
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Show help
show_help() {
    cat << EOF
Docker Management Script (docker-ms) v$VERSION

USAGE:
    docker-ms [OPTIONS]

OPTIONS:
    -i, --interactive       Launch interactive menu
    -l, --list             List all containers
    -a, --add CONTAINER    Add container to autostart
    -r, --remove CONTAINER Remove container from autostart
    -s, --show             Show autostart containers
    --start-autostart      Start all autostart containers (used by systemd)
    --install              Install script and systemd service
    --uninstall-service    Uninstall systemd service
    --update               Update script to latest version
    -h, --help             Show this help message
    -v, --version          Show version

EXAMPLES:
    docker-ms -i                    # Interactive menu
    docker-ms -l                    # List all containers
    docker-ms -a nginx              # Add nginx to autostart
    docker-ms -r nginx              # Remove nginx from autostart
    docker-ms --update              # Update script

AUTOSTART:
    Containers added to autostart will automatically start on system boot.
    The script detects compose files automatically and uses them when available.

FILES:
    Config: $CONFIG_DIR
    Service: $SERVICE_FILE

EOF
}

# Main script logic
main() {
    case "${1:-}" in
        -i|--interactive)
            interactive_menu
            ;;
        -l|--list)
            list_containers
            ;;
        -a|--add)
            [[ -z "${2:-}" ]] && { print_error "Container name required"; exit 1; }
            check_root
            add_to_autostart "$2"
            ;;
        -r|--remove)
            [[ -z "${2:-}" ]] && { print_error "Container name required"; exit 1; }
            check_root
            remove_from_autostart "$2"
            ;;
        -s|--show)
            print_info "Autostart containers:"
            get_autostart_containers
            ;;
        --start-autostart)
            start_autostart_containers
            ;;
        --install)
            install_script
            ;;
        --uninstall-service)
            uninstall_service
            ;;
        --update)
            self_update
            ;;
        -v|--version)
            echo "docker-ms version $VERSION"
            ;;
        -h|--help|"")
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
