#!/bin/bash
# Terrapin Vulnerability Scanner Automation Script for Debian
# Note: This scanner expects the target SSH server to support modern key exchange 
# algorithms. If the target only offers legacy methods (e.g., diffie-hellman-group-exchange-sha1
# or diffie-hellman-group14-sha1), the handshake will fail and the scanner may panic.
#
# This script updates the system, installs required dependencies and the Terrapin-Scanner (if needed),
# prompts for IP addresses to scan, runs the scans in the background, and displays nicely formatted JSON results.
# Extra output before the JSON (if any) is stripped using sed to avoid jq parsing errors.

# Check for root privileges (required for apt-get installs)
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Please run this script as root (e.g., using sudo)."
    exit 1
fi

echo "--------------------------------------------------"
echo " Terrapin Vulnerability Scanner Automation Script"
echo "--------------------------------------------------"
echo ""

# Step 1: Update package list and install dependencies
echo "[*] Updating package list..."
apt-get update -y

echo "[*] Installing dependencies: wget, git, golang-go, jq..."
apt-get install -y wget git golang-go jq

# Verify that Go is installed
if ! command -v go >/dev/null 2>&1; then
    echo "[!] Golang installation failed. Exiting."
    exit 1
fi

# Step 2: Check for Terrapin-Scanner; if not found, install it via 'go install'
if command -v Terrapin-Scanner >/dev/null 2>&1; then
    echo "[*] Terrapin-Scanner is already installed."
else
    echo "[*] Terrapin-Scanner not found. Installing via 'go install'..."
    # Set up Go environment variables
    export GOPATH="$HOME/go"
    export GOBIN="$GOPATH/bin"
    mkdir -p "$GOPATH"
    go install github.com/RUB-NDS/Terrapin-Scanner@latest

    if [ -f "$GOBIN/Terrapin-Scanner" ]; then
         echo "[*] Terrapin-Scanner installed successfully at $GOBIN/Terrapin-Scanner."
         # Add GOBIN to PATH if not already present (for the current session)
         if [[ ":$PATH:" != *":$GOBIN:"* ]]; then
             echo "[*] Adding $GOBIN to PATH for current session."
             export PATH="$PATH:$GOBIN"
         fi
    else
         echo "[!] Terrapin-Scanner installation failed. Exiting."
         exit 1
    fi
fi

echo "[*] All dependencies and Terrapin-Scanner are ready."
echo ""

# Step 3: Prompt user for IP address(es) to scan
read -p "Enter IP address(es) to scan (separated by spaces): " -a ip_array
if [ ${#ip_array[@]} -eq 0 ]; then
    echo "[!] No IP addresses provided. Exiting."
    exit 1
fi

echo ""
echo "[*] Starting Terrapin vulnerability scans..."

# Create a temporary directory for scan output files
temp_dir=$(mktemp -d -t terrapin_scan_XXXX)
echo "[*] Temporary directory for scan outputs: $temp_dir"

# Function to scan a single IP address
scan_ip() {
    local ip=$1
    echo "[*] Scanning ${ip}:22..."
    # Run the scanner in JSON output mode.
    # Redirect stderr to /dev/null and use sed to extract only the valid JSON part (starting with '{' or '[').
    Terrapin-Scanner --connect "${ip}:22" --json 2>/dev/null | sed -n '/^[{[]/,$p' > "$temp_dir/scan_${ip}.json" 2>&1
    echo "[*] Scan for ${ip} complete."
}

# Step 4: Launch scans in background for each IP
for ip in "${ip_array[@]}"; do
    scan_ip "$ip" &
done

# Wait for all background scans to finish
wait

echo ""
echo "----------------- Scan Results -------------------"
# Step 5: Display the results in a readable format
for ip in "${ip_array[@]}"; do
    echo "Results for ${ip}:"
    file="$temp_dir/scan_${ip}.json"
    if [ -s "$file" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq . "$file"
        else
            cat "$file"
        fi
    else
        echo "[!] No results for ${ip} or scan failed."
    fi
    echo "--------------------------------------------------"
done

# Clean up temporary files
rm -rf "$temp_dir"

echo "[*] All scans completed. Exiting."
