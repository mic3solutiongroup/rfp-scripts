# N8S - Nginx Router Manager

Advanced nginx reverse proxy manager with Docker and n8n integration. Manage multiple services through a single port with path-based routing.

## Features

- **Menu-driven interface** for easy configuration
- **Persistent configuration** across sessions
- **Docker integration** with automatic installation
- **n8n workflow automation** with special nginx configuration
- **Dynamic route management** - bind internal ports to nginx paths
- **Auto-update capability** from GitHub repository
- **Global command access** via `n8s` command

## Quick Start
```bash
wget https://raw.githubusercontent.com/mic3solutiongroup/rfp-scripts/refs/heads/main/n8s.sh
chmod +x n8s.sh
sudo mv n8s.sh /usr/local/bin/n8s
sudo n8s
```

## Requirements

- Ubuntu/Debian-based system
- Root or sudo access
- Port 8443 available (configurable)

## Installation Steps

### 1. Install Docker (if needed)
```bash
sudo n8s
# Select option 8: Install Docker
```

### 2. Install n8n
```bash
sudo n8s
# Select option 1: Install n8n
```

n8n will be installed at: `http://YOUR_IP:8443/n8n/`

Docker Compose location: `~/rfp/n8n/docker-compose.yml`

## Usage

### Launch Manager
```bash
sudo n8s
```

### Update Script
```bash
sudo n8s -update
```
or
```bash
sudo n8s update
```

## Menu Options
```
1) Install n8n          - Full n8n setup with Docker and nginx
2) Add Route            - Create new path-to-port mapping
3) List Routes          - View all configured routes
4) Remove Route         - Delete existing route
5) Change Settings      - Modify port, IP, or n8n directory
6) Update Script        - Pull latest version from GitHub
7) Docker Status        - Check Docker installation and containers
8) Install Docker       - Install Docker and Docker Compose
9) Exit                 - Close manager
```

## Configuration

### Default Settings
- **Nginx Port**: 8443
- **n8n Directory**: `~/rfp/n8n/`
- **n8n Internal Port**: 5678
- **Config Location**: `/etc/n8s/config.env`
- **Routes Directory**: `/etc/nginx/routes-8443/`

### Add Custom Route Example
```
Select option: 2
Enter nginx path: /api/
Enter internal port: 3000
Route name: myapi
```

Result: `http://YOUR_IP:8443/api/` → `localhost:3000`

## n8n Configuration

The script creates a special nginx configuration for n8n that handles:
- WebSocket connections for real-time updates
- Origin header workarounds for non-standard ports
- Path-based routing under `/n8n/`
- Proper proxy headers for workflow webhooks

### n8n Environment Variables
```yaml
N8N_PORT=5678
N8N_PATH=/n8n/
N8N_EDITOR_BASE_URL=http://YOUR_IP:8443/n8n/
WEBHOOK_URL=http://YOUR_IP:8443/
N8N_ALLOWED_ORIGINS=*
N8N_PUSH_BACKEND=websocket
```

## File Locations
```
/usr/local/bin/n8s                    # Main script
/etc/n8s/config.env                   # Configuration file
/etc/nginx/sites-available/8443-router.conf  # Main nginx config
/etc/nginx/routes-8443/               # Route configurations
~/rfp/n8n/docker-compose.yml          # n8n Docker Compose
```

## Firewall Configuration

If using UFW:
```bash
sudo ufw allow 8443/tcp
sudo ufw reload
```

## Docker Compose Management

### View n8n logs
```bash
cd ~/rfp/n8n
docker compose logs -f
```

### Restart n8n
```bash
cd ~/rfp/n8n
docker compose restart
```

### Stop n8n
```bash
cd ~/rfp/n8n
docker compose down
```

### Start n8n
```bash
cd ~/rfp/n8n
docker compose up -d
```

## Advanced Usage

### Change nginx port
```bash
sudo n8s
# Select option 5: Change Settings
# Enter new nginx port: 9000
```

### Change server IP
```bash
sudo n8s
# Select option 5: Change Settings
# Enter server IP: your.domain.com
```

### Multiple service routing
```bash
# Add as many routes as needed
/api/      → localhost:3000
/app/      → localhost:4000
/service/  → localhost:5000
/n8n/      → localhost:5678
```

## Troubleshooting

### n8n not accessible
```bash
# Check Docker status
docker ps

# Check n8n logs
cd ~/rfp/n8n
docker compose logs

# Verify nginx configuration
nginx -t
systemctl status nginx
```

### Route not working
```bash
# Test nginx config
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# Check route files
ls -la /etc/nginx/routes-8443/
```

### Port already in use
```bash
# Change nginx port
sudo n8s
# Select option 5: Change Settings
```

### Docker permission denied
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Logout and login again
```

## Security Notes

- Change default port 8443 for production
- Use HTTPS with SSL certificates
- Restrict `N8N_ALLOWED_ORIGINS` in production
- Implement authentication for exposed services
- Use firewall rules to limit access

## Update History

Configuration and routes persist across updates. Run `n8s -update` to get latest features.

## Contributing

Submit issues and pull requests at:
https://github.com/mic3solutiongroup/rfp-scripts

## License

MIT License

## Support

For issues or questions, please open an issue on GitHub.

## Credits

Built for easy nginx reverse proxy management with Docker and n8n integration.
