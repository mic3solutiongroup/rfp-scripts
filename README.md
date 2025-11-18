# Docker Management Script (docker-ms)

A comprehensive Docker container management tool with auto-start capabilities, smart compose detection, and an interactive menu interface.

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Bash](https://img.shields.io/badge/bash-5.0+-orange.svg)

## 🚀 Features

- **Auto-start on Boot**: Configure specific containers to start automatically after system reboot
- **Smart Compose Detection**: Automatically detects and uses docker-compose files
- **Interactive Menu**: User-friendly numbered menu system for easy management
- **Self-Updating**: Update script directly from GitHub repository
- **Systemd Integration**: Native Linux service integration for reliable boot startup
- **Container Management**: View, configure, and manage both compose and standalone containers
- **Path Mapping**: Automatically stores and uses compose file paths
- **Color-Coded Output**: Clear visual feedback for operations
- **Error Handling**: Comprehensive error checking and user-friendly messages

## 📋 Prerequisites

- Linux system with systemd
- Docker installed and running
- Docker Compose (optional, for compose-based containers)
- Root/sudo access for installation
- `curl` for updates

## 📦 Installation

### Quick Install

```bash
# Download and install in one command
curl -fsSL https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/docker-ms.sh | sudo bash -s -- --install
```

### Manual Install

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/docker-ms.sh -o docker-ms.sh

# Make it executable
chmod +x docker-ms.sh

# Install system-wide (creates systemd service)
sudo ./docker-ms.sh --install
```

### What Gets Installed

- Script: `/usr/local/bin/docker-ms`
- Config directory: `/etc/docker-ms/`
- Autostart config: `/etc/docker-ms/autostart.conf`
- Compose mapping: `/etc/docker-ms/compose-map.conf`
- Systemd service: `/etc/systemd/system/docker-ms-autostart.service`

## 🎯 Usage

### Command Line Interface

```bash
# Show help menu
docker-ms
docker-ms --help

# Launch interactive menu
docker-ms -i
docker-ms --interactive

# List all containers
docker-ms -l
docker-ms --list

# Add container to autostart
docker-ms -a nginx
docker-ms --add nginx

# Remove container from autostart
docker-ms -r nginx
docker-ms --remove nginx

# Show autostart containers
docker-ms -s
docker-ms --show

# Update script to latest version
docker-ms --update

# Manually start autostart containers
docker-ms --start-autostart

# Check version
docker-ms -v
docker-ms --version
```

### Interactive Menu

Launch the interactive menu with:

```bash
docker-ms -i
```

**Menu Options:**

```
1) List all containers              - View all Docker containers with type info
2) Show autostart containers        - Display containers configured for autostart
3) Add container to autostart       - Add a container to boot autostart list
4) Remove container from autostart  - Remove a container from autostart list
5) Start autostart containers now   - Test autostart without rebooting
6) Set/Update compose file path     - Manually configure compose file location
7) Install/Reinstall systemd service - Setup or repair boot service
8) Uninstall systemd service        - Remove boot autostart service
9) Update docker-ms script          - Update to latest version from GitHub
0) Exit                            - Close the menu
```

## 💡 Examples

### Basic Workflow

```bash
# 1. Launch interactive menu
docker-ms -i

# 2. Select option 1 to view all containers
# 3. Select option 3 to add containers to autostart
# 4. Select option 5 to test (starts containers immediately)
# 5. Reboot to verify auto-start works
```

### Command Line Workflow

```bash
# View all containers
docker-ms -l

# Add multiple containers to autostart
sudo docker-ms -a nginx
sudo docker-ms -a postgres
sudo docker-ms -a redis

# View autostart list
docker-ms -s

# Test autostart without rebooting
sudo docker-ms --start-autostart

# Remove a container from autostart
sudo docker-ms -r redis
```

### Update Script

```bash
# Update to latest version from GitHub
sudo docker-ms --update
```

## 🔧 How It Works

### Auto-Start Process

1. **Boot Sequence**: System boots → systemd starts docker → docker-ms service runs
2. **Container Detection**: Script reads `/etc/docker-ms/autostart.conf`
3. **Type Detection**: Checks if container is compose-based or standalone
4. **Compose Lookup**: Retrieves compose file path from `/etc/docker-ms/compose-map.conf`
5. **Smart Start**: Uses `docker-compose up` for compose containers, `docker start` for standalone

### Compose Detection

The script automatically detects compose files using:
- Docker labels: `com.docker.compose.project.config_files`
- Working directory: `com.docker.compose.project.working_dir`
- Fallback: Manual path configuration via menu option 6

### Container Types

- **Compose Containers**: Started using `docker-compose -f <file> up -d <container>`
- **Standalone Containers**: Started using `docker start <container>`

## 📁 Configuration Files

### `/etc/docker-ms/autostart.conf`
Contains list of containers to auto-start (one per line):
```
nginx
postgres
redis
app-backend
```

### `/etc/docker-ms/compose-map.conf`
Maps containers to their compose file paths:
```
nginx=/opt/webserver/docker-compose.yml
app-backend=/home/user/projects/app/docker-compose.yml
```

## 🔄 Systemd Service

The script creates a systemd service that:
- Runs automatically on boot
- Starts after Docker is ready
- Executes `docker-ms --start-autostart`
- Logs to system journal

### Service Management

```bash
# Check service status
sudo systemctl status docker-ms-autostart

# View service logs
sudo journalctl -u docker-ms-autostart -f

# Manually start service
sudo systemctl start docker-ms-autostart

# Restart service
sudo systemctl restart docker-ms-autostart

# Disable service (keeps script installed)
sudo systemctl disable docker-ms-autostart

# Re-enable service
sudo systemctl enable docker-ms-autostart
```

## 🛠️ Troubleshooting

### Containers not starting on boot

```bash
# Check if service is enabled
sudo systemctl is-enabled docker-ms-autostart

# Check service status
sudo systemctl status docker-ms-autostart

# View detailed logs
sudo journalctl -u docker-ms-autostart -b

# Manually test autostart
sudo docker-ms --start-autostart
```

### Compose file not detected

```bash
# Manually set compose file path
docker-ms -i
# Select option 6 and enter container name and compose file path
```

### Script not found after installation

```bash
# Verify installation
which docker-ms

# Reload shell configuration
hash -r

# Reinstall if needed
sudo ./docker-ms.sh --install
```

### Update fails

```bash
# Check internet connectivity
curl -I https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/docker-ms.sh

# Manually download and install
curl -fsSL https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/docker-ms.sh -o /tmp/docker-ms.sh
sudo mv /tmp/docker-ms.sh /usr/local/bin/docker-ms
sudo chmod +x /usr/local/bin/docker-ms
```

## 🔐 Permissions

Most operations require root/sudo privileges:
- ✅ Viewing containers and autostart list (no sudo)
- ⚠️ Adding/removing from autostart (requires sudo)
- ⚠️ Installing/updating script (requires sudo)
- ⚠️ Managing systemd service (requires sudo)

## 🗑️ Uninstallation

```bash
# Remove systemd service
sudo docker-ms --uninstall-service

# Remove script and config (manual)
sudo rm -f /usr/local/bin/docker-ms
sudo rm -rf /etc/docker-ms
```

## 📊 Container Status Display

When listing containers, you'll see:

```
===================================================================
CONTAINER ID    NAME                      STATUS          TYPE
===================================================================
a1b2c3d4e5f6   nginx                     Up 2 hours      compose
b2c3d4e5f6g7   postgres                  Up 3 hours      compose
c3d4e5f6g7h8   redis                     Up 1 hour       standalone
===================================================================
```

## 🎨 Color Legend

- 🟢 **Green (✓)**: Success messages
- 🔵 **Blue (ℹ)**: Informational messages
- 🟡 **Yellow (⚠)**: Warning messages
- 🔴 **Red (✗)**: Error messages

## 🤝 Contributing

This script is maintained at:
```
https://github.com/mic3solutiongroup/rfp-scripts
```

To contribute:
1. Fork the repository
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## 📝 License

MIT License - Free to use and modify

## 🐛 Known Issues

- Requires systemd (not compatible with SysV init)
- Docker must be fully started before script runs
- Compose v2 (`docker compose`) may require adjustments in some environments

## 🔮 Future Enhancements

- [ ] Support for Docker Swarm services
- [ ] Container dependency ordering
- [ ] Health check integration
- [ ] Web UI dashboard
- [ ] Email notifications on failures
- [ ] Support for podman
- [ ] Backup/restore configurations

## 📞 Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Check troubleshooting section above
- Review systemd logs: `journalctl -u docker-ms-autostart`

## ⚡ Quick Reference

```bash
docker-ms -i          # Interactive menu (most common)
docker-ms -l          # List containers
docker-ms -a NAME     # Add to autostart
docker-ms -r NAME     # Remove from autostart
docker-ms --update    # Update script
```

---
Last Updated: November 2025
