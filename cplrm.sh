#!/bin/bash

# CloudPanel Complete Removal Script
# This script removes CloudPanel and all associated PHP versions

set -e  # Exit on error

echo "================================================"
echo "CloudPanel & PHP Complete Removal Script"
echo "================================================"
echo ""
echo "WARNING: This will remove CloudPanel and all PHP versions!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo ""
echo "[1/10] Stopping PHP-FPM services..."
sudo systemctl stop php7.1-fpm php7.2-fpm php7.3-fpm php7.4-fpm php8.0-fpm php8.1-fpm php8.2-fpm php8.3-fpm php8.4-fpm 2>/dev/null || true

echo ""
echo "[2/10] Removing all PHP packages (PURGE)..."
sudo apt-get remove --purge php* -y 2>/dev/null || true

echo ""
echo "[3/10] Force removing PHP versions if needed..."
sudo dpkg --remove --force-all php7.1 php7.2 php7.3 php7.4 php8.0 php8.1 php8.2 php8.3 php8.4 2>/dev/null || true

echo ""
echo "[4/10] Removing PHP configuration directories..."
sudo rm -rf /etc/php
sudo rm -rf /usr/lib/php
sudo rm -rf /var/lib/php

echo ""
echo "[5/10] Stopping CloudPanel, Nginx, and MySQL services..."
sudo systemctl stop cloudpanel nginx mysql 2>/dev/null || true

echo ""
echo "[6/10] Force removing broken CloudPanel package..."
sudo dpkg --remove --force-remove-reinstreq cloudpanel 2>/dev/null || true
sudo dpkg --purge --force-all cloudpanel 2>/dev/null || true

echo ""
echo "[7/10] Removing CloudPanel package info files..."
sudo rm -rf /var/lib/dpkg/info/cloudpanel.* 2>/dev/null || true

echo ""
echo "[8/10] Reconfiguring dpkg..."
sudo dpkg --configure -a

echo ""
echo "[9/10] Cleaning up packages..."
sudo apt-get autoremove -y
sudo apt-get autoclean -y
sudo apt-get install -f -y

echo ""
echo "[10/10] Removing CloudPanel configuration directories..."
sudo rm -rf /etc/cloudpanel
sudo rm -rf /home/cloudpanel
sudo rm -rf /var/www/cloudpanel
sudo rm -rf /etc/nginx
sudo rm -rf /usr/lib/php
sudo rm -rf /var/log/mysql
sudo rm -rf /etc/mysql
sudo rm -rf /tmp/cloudpanel
sudo rm -rf /usr/share/doc/cloudpanel

echo ""
echo "[11/11] Removing CloudPanel and PHP repositories..."
sudo rm -f /etc/apt/sources.list.d/*cloudpanel*.list
sudo rm -f /etc/apt/sources.list.d/*php*.list

echo ""
echo "Updating package lists..."
sudo apt-get update

echo ""
echo "================================================"
echo "Removal Complete!"
echo "================================================"
echo ""
echo "Verification:"
echo "-------------"

# Check for remaining PHP packages
PHP_PACKAGES=$(dpkg -l | grep php | wc -l)
echo "Remaining PHP packages: $PHP_PACKAGES"

# Check for remaining CloudPanel packages
CP_PACKAGES=$(dpkg -l | grep cloudpanel | wc -l)
echo "Remaining CloudPanel packages: $CP_PACKAGES"

# Check for PHP binary
if command -v php &> /dev/null; then
    echo "PHP binary: STILL EXISTS at $(which php)"
else
    echo "PHP binary: REMOVED ✓"
fi

# Check for CloudPanel directories
if [ -d "/etc/cloudpanel" ]; then
    echo "CloudPanel config: STILL EXISTS"
else
    echo "CloudPanel config: REMOVED ✓"
fi

echo ""
echo "If you see any remaining packages or files above,"
echo "you can manually remove them or run specific cleanup commands."
echo ""
echo "Disk space freed: Run 'df -h' to check"
echo "================================================"
