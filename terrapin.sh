#!/bin/bash
# Improved Terrapin Vulnerability Scanner Automation Script for Debian
# This script checks for required commands and installs the corresponding packages
# only if they are missing. For example, if "go" is missing, it installs "golang-go".
#
# It then verifies that Terrapin-Scanner is installed and performs the scan.
# (Extra output is filtered so that only the valid JSON portion is passed to jq.)
#
# Note: If the target SSH server only supports legacy key exchange methods,
# Terrapin-Scanner may panic due to a failed handshake.

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Please run this script as root (e.g., using sudo)."
    exit 1
fi

echo "--------------------------------------------------"
echo " Terrapin Vulnerability Scanner Automation Script"
echo "--------------------------------------------------"
echo ""

# Define a mapping of command names to package names (for apt-get installation)
declare -A pkg_map
pkg_map=(
    ["wget"]="wget"
    ["git"]="git"
    ["go"]="golang-go"
    ["jq"]="jq"
)

# List of required commands to check for
required_commands=("wget" "git" "go" "jq")

# Check for missing dependencies
missing_pkgs=()
for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_pkgs+=("${pkg_map[$cmd]}")
    fi
done

if [ ${#missing_pkgs[@]} -gt 0 ]; then
    echo "[*] The following dependencies are missing: ${missing_pkgs[*]}"
    echo "[*] Updating package list and installing missing dependencies..."
    apt-get update -qq
    apt-get install -y "${missing_pkgs[@]}"
fi

# Verify that Go is available after installation
if ! command -v go >/dev/null 2>&1; then
    echo "[!] Go is required but is still not installed. Exiting."
    exit 1
fi

# Check for Terrapin-Scanner; if missing, install it via go install.
if ! command -v Terrapin-Scanner >/dev/null 2>&1; then
    echo "[*] Installing Terrapin-Scanner via 'go install'..."
    export GOPATH="$HOME/go"
    export GOBIN="$GOPATH/bin"
    mkdir -p "$GOPATH"
    go install github.com/RUB-NDS/Terrapin-Scanner@latest
    if [ -f "$GOBIN/Terrapin-Scanner" ]; then
         echo "[*] Terrapin-Scanner installed successfully at $GOBIN/Terrapin-Scanner."
         # Add GOBIN to PATH for current session if not already present
         if [[ ":$PATH:" != *":$GOBIN:"* ]]; then
             export PATH="$PATH:$GOBIN"
         fi
    else
         echo "[!] Terrapin-Scanner installation failed. Exiting."
         exit 1
    fi
fi

echo "[*] All dependencies and Terrapin-Scanner are ready."
echo ""

# Prompt user for IP address(es) to scan
read -p "Enter IP address(es) to scan (separated by spaces): " -a ip_array
if [ ${#ip_array[@]} -eq 0 ]; then
    echo "[!] No IP addresses provided. Exiting."
    exit 1
fi

echo ""
echo "[*] Starting Terrapin vulnerability scans..."

# Create a temporary directory for scan output files
temp_dir=$(mktemp -d -t terrapin_scan_XXXX)

# Function to scan a single IP address
scan_ip() {
    local ip=$1
    echo "[*] Scanning ${ip}:22..."
    # Run the scanner in JSON output mode.
    # Redirect stderr to /dev/null and use sed to output only lines starting with '{' or '['
    Terrapin-Scanner --connect "${ip}:22" --json 2>/dev/null | sed -n '/^[{[]/,$p' > "$temp_dir/scan_${ip}.json" 2>&1
    echo "[*] Scan for ${ip} complete."
}

# Launch scans in background for each IP
for ip in "${ip_array[@]}"; do
    scan_ip "$ip" &
done

# Wait for all background scans to finish
wait

echo ""
echo "----------------- Scan Results -------------------"
# Display the results in a readable format
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
