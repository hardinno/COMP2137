#!/bin/bash

# Assign 2 - Ubuntu Server Configuration
# Script to configure the target server to the required state.
# It is designed to be idempotent.

set -u

# -----------------------------
# Configuration
# -----------------------------

NETPLAN_FILE="/etc/netplan/10-lxc.yaml"
HOSTS_FILE="/etc/hosts"

TARGET_IP="192.168.16.21"
TARGET_NETWORK="192.168.16.0/24"
GATEWAY="192.168.16.2"

USERS=(
    dennis
    aubrey
    captain
    snibbles
    brownie
    scooter
    sandy
    perrier
    cindy
    tiger
    yoda
)

DENNIS_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"

# -----------------------------
# Functions
# -----------------------------

print_header() {
    echo
    echo "=============================================="
    echo "$1"
    echo "=============================================="
}

print_status() {
    echo "[INFO] $1"
}

print_success() {
    echo "[OK]   $1"
}

print_error() {
    echo "[ERROR] $1" >&2
}

# -----------------------------
# Root check
# -----------------------------

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root."
    echo "Please run: sudo $0"
    exit 1
fi

print_header "Assignment 2 Server Configuration"

print_status "Running on host: $(hostname)"

# -----------------------------
# Network Configuration
# -----------------------------

print_header "Configuring Network"

if [ ! -f "$NETPLAN_FILE" ]; then
    print_error "Netplan configuration file not found: $NETPLAN_FILE"
    exit 1
fi

# Back up Netplan configuration once
if [ ! -f "${NETPLAN_FILE}.assignment2-backup" ]; then
    cp "$NETPLAN_FILE" "${NETPLAN_FILE}.assignment2-backup"
    print_status "Created Netplan backup."
fi

# Change only eth1 address
if grep -q "addresses: \[192.168.16.21/24\]" "$NETPLAN_FILE"; then

    print_status "eth1 already has address 192.168.16.21/24."

elif grep -qE "addresses: \[192\.168\.16\.[0-9]+/24\]" "$NETPLAN_FILE"; then

    sed -i -E \
        's/addresses: \[192\.168\.16\.[0-9]+\/24\]/addresses: [192.168.16.21\/24]/' \
        "$NETPLAN_FILE"

    print_success "Updated the 192.168.16 network address to 192.168.16.21/24."

else

    print_error "Could not find the 192.168.16 network configuration."
    exit 1

fi

# -----------------------------
# /etc/hosts Configuration
# -----------------------------

print_header "Configuring /etc/hosts"

# Check whether the correct server1 entry already exists
if grep -qE "^[[:space:]]*$TARGET_IP[[:space:]]+server1([[:space:]]|$)" "$HOSTS_FILE"; then

    print_status "/etc/hosts already contains the correct server1 entry."

else

    # Remove any old 192.168.16.x address associated with server1
    sed -i '/^[[:space:]]*192\.168\.16\.[0-9]\+[[:space:]]\+server1[[:space:]]*$/d' "$HOSTS_FILE"

    echo "$TARGET_IP server1" >> "$HOSTS_FILE"

    print_success "Updated /etc/hosts with $TARGET_IP server1."

fi

# -----------------------------
# Package Installation
# -----------------------------

print_header "Installing Required Software"

export DEBIAN_FRONTEND=noninteractive

print_status "Updating package information..."
if apt-get update; then
    print_success "Package information updated."
else
    print_error "apt-get update failed."
    exit 1
fi

for package in apache2 squid; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
        print_status "$package is already installed."
    else
        print_status "Installing $package..."
        if apt-get install -y "$package"; then
            print_success "$package installed."
        else
            print_error "Failed to install $package."
            exit 1
        fi
    fi
done

# -----------------------------
# Enable and Start Services
# -----------------------------

print_header "Configuring Services"

for service in apache2 squid; do
    print_status "Enabling $service..."

    if systemctl enable "$service" >/dev/null 2>&1; then
        print_success "$service enabled."
    else
        print_error "Could not enable $service."
    fi

    print_status "Starting $service..."

    if systemctl start "$service" >/dev/null 2>&1; then
        print_success "$service started."
    else
        print_error "Could not start $service."
    fi
done

# -----------------------------
# User Accounts
# -----------------------------

print_header "Configuring User Accounts"

for username in "${USERS[@]}"; do

    if id "$username" >/dev/null 2>&1; then
        print_status "User $username already exists."
    else
        print_status "Creating user $username..."

        if useradd -m -d "/home/$username" -s /bin/bash "$username"; then
            print_success "Created user $username."
        else
            print_error "Failed to create user $username."
            continue
        fi
    fi

    # Ensure home directory exists
    if [ ! -d "/home/$username" ]; then
        mkdir -p "/home/$username"
        chown "$username:$username" "/home/$username"
        chmod 700 "/home/$username"
        print_success "Created home directory for $username."
    fi

    # Ensure Bash is the default shell
    CURRENT_SHELL=$(getent passwd "$username" | cut -d: -f7)

    if [ "$CURRENT_SHELL" != "/bin/bash" ]; then
        usermod -s /bin/bash "$username"
        print_success "Changed default shell for $username to /bin/bash."
    else
        print_status "$username already uses /bin/bash."
    fi

    # SSH directory
    SSH_DIR="/home/$username/.ssh"

    if [ ! -d "$SSH_DIR" ]; then
        mkdir -p "$SSH_DIR"
        print_success "Created SSH directory for $username."
    fi

    chmod 700 "$SSH_DIR"
    chown "$username:$username" "$SSH_DIR"

    # RSA key
    if [ ! -f "$SSH_DIR/id_rsa" ]; then
        print_status "Generating RSA key for $username..."

        if sudo -u "$username" ssh-keygen -t rsa -b 3072 -f "$SSH_DIR/id_rsa" -N "" -q; then
            print_success "Generated RSA key for $username."
        else
            print_error "Failed to generate RSA key for $username."
        fi
    else
        print_status "RSA key already exists for $username."
    fi

    # Ed25519 key
    if [ ! -f "$SSH_DIR/id_ed25519" ]; then
        print_status "Generating Ed25519 key for $username..."

        if sudo -u "$username" ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -q; then
            print_success "Generated Ed25519 key for $username."
        else
            print_error "Failed to generate Ed25519 key for $username."
        fi
    else
        print_status "Ed25519 key already exists for $username."
    fi

    AUTH_KEYS="$SSH_DIR/authorized_keys"

    touch "$AUTH_KEYS"

    # Add user's RSA public key
    if [ -f "$SSH_DIR/id_rsa.pub" ]; then
        RSA_KEY=$(cat "$SSH_DIR/id_rsa.pub")

        if ! grep -Fxq "$RSA_KEY" "$AUTH_KEYS"; then
            echo "$RSA_KEY" >> "$AUTH_KEYS"
            print_success "Added RSA public key for $username."
        else
            print_status "RSA public key already authorized for $username."
        fi
    fi

    # Add user's Ed25519 public key
    if [ -f "$SSH_DIR/id_ed25519.pub" ]; then
        ED25519_KEY=$(cat "$SSH_DIR/id_ed25519.pub")

        if ! grep -Fxq "$ED25519_KEY" "$AUTH_KEYS"; then
            echo "$ED25519_KEY" >> "$AUTH_KEYS"
            print_success "Added Ed25519 public key for $username."
        else
            print_status "Ed25519 public key already authorized for $username."
        fi
    fi

    chown "$username:$username" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"

    # Fix ownership of SSH files
    chown -R "$username:$username" "$SSH_DIR"

done

# -----------------------------
# Dennis Sudo Access
# -----------------------------

print_header "Configuring Dennis"

if id -nG dennis | grep -qw sudo; then
    print_status "Dennis is already a member of the sudo group."
else
    usermod -aG sudo dennis
    print_success "Added dennis to the sudo group."
fi

DENNIS_AUTH="/home/dennis/.ssh/authorized_keys"

if grep -Fxq "$DENNIS_KEY" "$DENNIS_AUTH"; then
    print_status "Dennis's required SSH public key is already authorized."
else
    echo "$DENNIS_KEY" >> "$DENNIS_AUTH"
    print_success "Added required SSH key for Dennis."
fi

chown dennis:dennis "$DENNIS_AUTH"
chmod 600 "$DENNIS_AUTH"

# -----------------------------
# Apply Netplan
# -----------------------------

print_header "Applying Network Configuration"

if netplan generate; then
    print_success "Netplan configuration generated successfully."
else
    print_error "Netplan configuration generation failed."
    exit 1
fi

if netplan apply; then
    print_success "Network configuration applied successfully."
else
    print_error "Netplan apply failed."
    exit 1
fi

# -----------------------------
# Final Verification
# -----------------------------

print_header "Final Verification"

echo
echo "Hostname:"
hostname

echo
echo "Network interfaces:"
ip addr

echo
echo "Server1 hosts entry:"
grep "server1" /etc/hosts || true

echo
echo "Apache2 status:"
systemctl is-active apache2 || true

echo
echo "Squid status:"
systemctl is-active squid || true

echo
echo "Configured users:"
for username in "${USERS[@]}"; do
    if id "$username" >/dev/null 2>&1; then
        echo "[OK] $username"
    else
        echo "[ERROR] $username is missing"
    fi
done

echo
echo "=============================================="
echo "Assignment 2 configuration completed."
echo "=============================================="
