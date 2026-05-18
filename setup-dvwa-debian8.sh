#!/bin/bash
#
# DVWA (Damn Vulnerable Web Application) Setup Script for Debian 8 (Jessie)
# Usage: curl -sSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/setup-dvwa-debian8.sh | bash
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; exit 1; }

# ── Check root ──────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root. Use: curl ... | sudo bash"
fi

# ── Fix Debian 8 EOL repos — switch to archive ─────────────────────────────
log "Configuring Debian 8 archive repositories..."
cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian/ jessie main contrib non-free
deb http://archive.debian.org/debian/ jessie-updates main contrib non-free
deb http://archive.debian.org/debian-security/ jessie/updates main contrib non-free
EOF

cat > /etc/apt/apt.conf.d/99no-check-valid-until <<'EOF'
Acquire::Check-Valid-Until "false";
EOF

# ── Update system ───────────────────────────────────────────────────────────
log "Updating package lists..."
apt-get update -o Acquire::Check-Valid-Until=false -qq

log "Upgrading installed packages (this may take a while)..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

# ── Set MySQL root password ─────────────────────────────────────────────────
DB_ROOT_PASS="dvwa"
DB_NAME="dvwa"
DB_USER="dvwa"
DB_PASS="p@ssw0rd"

log "Preseeding MySQL root password..."
echo "mysql-server mysql-server/root_password password ${DB_ROOT_PASS}" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password ${DB_ROOT_PASS}" | debconf-set-selections

# ── Install packages ────────────────────────────────────────────────────────
log "Installing Apache, MySQL, PHP, and dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    apache2 \
    mysql-server \
    mysql-client \
    php5 \
    php5-mysql \
    php5-gd \
    libapache2-mod-php5 \
    unzip \
    wget \
    curl \
    git

# ── Enable Apache modules ───────────────────────────────────────────────────
log "Enabling Apache rewrite module..."
a2enmod rewrite

# ── Allow .htaccess overrides ───────────────────────────────────────────────
log "Configuring Apache for DVWA..."
APACHE_DEFAULT="/etc/apache2/sites-available/000-default.conf"
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/s/AllowOverride None/AllowOverride All/' "$APACHE_DEFAULT"
sed -i '/<Directory \/var\/www\/html>/,/<\/Directory>/s/AllowOverride None/AllowOverride All/' "$APACHE_DEFAULT"

# Add virtualhost block
cat > /etc/apache2/sites-available/dvwa.conf <<'VIRTUALHOST'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/dvwa

    <Directory /var/www/html/dvwa>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/dvwa_error.log
    CustomLog ${APACHE_LOG_DIR}/dvwa_access.log combined
</VirtualHost>
VIRTUALHOST

# ── Disable default site (optional) and enable dvwa ─────────────────────────
a2dissite 000-default 2>/dev/null || true
a2ensite dvwa
a2enmod rewrite

# ── Download DVWA ───────────────────────────────────────────────────────────
log "Downloading DVWA..."
cd /tmp
rm -rf DVWA 2>/dev/null || true
git clone https://github.com/digininja/DVWA.git

log "Copying DVWA to /var/www/html/dvwa..."
rm -rf /var/www/html/dvwa 2>/dev/null || true
cp -r DVWA /var/www/html/dvwa
cp /var/www/html/dvwa/config/config.inc.php.dist /var/www/html/dvwa/config/config.inc.php

# ── Configure DVWA config ───────────────────────────────────────────────────
log "Configuring DVWA database credentials..."
CONFIG_FILE="/var/www/html/dvwa/config/config.inc.php"

sed -i "s/\$_DVWA\[ 'db_user' \]     = 'dvwa';/\$_DVWA[ 'db_user' ]     = '${DB_USER}';/" "$CONFIG_FILE"
sed -i "s/\$_DVWA\[ 'db_password' \] = 'p@ssw0rd';/\$_DVWA[ 'db_password' ] = '${DB_PASS}';/" "$CONFIG_FILE"

# Extended config for PHP 5.6 on Debian 8
if ! grep -q "db_port" "$CONFIG_FILE"; then
    sed -i "/\$_DVWA\[ 'db_password' \]/a\\
\$_DVWA[ 'db_port' ] = '3306';" "$CONFIG_FILE"
fi

# Add Google reCAPTCHA keys (dummy, required for setup)
sed -i "s/\$_DVWA\[ 'recaptcha_public_key' \]  = '';/\$_DVWA[ 'recaptcha_public_key' ]  = '6LdK7xITAAzzAAJQTfL7fu6I-0aPl8KHHieAT_yJg';/" "$CONFIG_FILE"
sed -i "s/\$_DVWA\[ 'recaptcha_private_key' \] = '';/\$_DVWA[ 'recaptcha_private_key' ] = '6LdK7xITAzzAAL_uw9YXVUOPoIHPZLfw2K1n5NVQ';/" "$CONFIG_FILE"

# ── Set permissions ─────────────────────────────────────────────────────────
log "Setting file permissions..."
chown -R www-data:www-data /var/www/html/dvwa
chmod -R 755 /var/www/html/dvwa
chmod 755 /var/www/html/dvwa/hackable/uploads/
chmod 755 /var/www/html/dvwa/external/phpids/0.6/lib/IDS/tmp/phpids_log.txt

# Fix PHP allow_url_include for DVWA
PHP_INI="/etc/php5/apache2/php.ini"
sed -i 's/allow_url_fopen = Off/allow_url_fopen = On/' "$PHP_INI"
sed -i 's/allow_url_include = Off/allow_url_include = On/' "$PHP_INI"

# Display errors for DVWA
sed -i 's/display_errors = Off/display_errors = On/' "$PHP_INI"
sed -i 's/display_startup_errors = Off/display_startup_errors = On/' "$PHP_INI"

# ── Restart Apache ──────────────────────────────────────────────────────────
log "Restarting Apache..."
service apache2 restart

# ── Wait for MySQL ──────────────────────────────────────────────────────────
sleep 2

# ── Create DVWA database and user ───────────────────────────────────────────
log "Creating DVWA database and user..."
mysql -u root -p"${DB_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
SQL

# ── Cleanup ─────────────────────────────────────────────────────────────────
rm -rf /tmp/DVWA

# ── Get IP ──────────────────────────────────────────────────────────────────
SERVER_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              DVWA Setup Complete!                       ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  URL:      http://${SERVER_IP}/                         ║"
echo "║  DB Host:  localhost                                    ║"
echo "║  DB Name:  ${DB_NAME}                                       ║"
echo "║  DB User:  ${DB_USER}                                       ║"
echo "║  DB Pass:  ${DB_PASS}                                   ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Next steps:                                            ║"
echo "║  1. Visit http://${SERVER_IP}/setup.php                 ║"
echo "║  2. Click 'Create / Reset Database'                     ║"
echo "║  3. Login: admin / password                            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
