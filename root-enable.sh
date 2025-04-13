#!/bin/bash

# Simple script to ensure 'PermitRootLogin yes' is active in sshd_config.

# === Configuration ===
SSH_CONFIG_FILE="/etc/ssh/sshd_config"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d_%H%M%S)" # Timestamped backup
BACKUP_FILE="${SSH_CONFIG_FILE}${BACKUP_SUFFIX}"
PARAM_TO_SET="PermitRootLogin"
VALUE_TO_SET="yes"

# === Colors ===
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# === Helper Functions ===
print_info() { echo -e "${BLUE}INFO: $1${NC}"; }
print_success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
print_error() { echo -e "${RED}ERROR: $1${NC}"; }

# === Main Script ===
echo -e "${BOLD}--- Simple Root SSH Enable Script ---${NC}"
echo ""

# --- Step 1: Check Root Privileges ---
print_info "Checking for root privileges..."
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (or using sudo)."
   exit 1
else
   print_success "Running as root."
fi
echo ""

# --- Step 2: Check if Already Enabled ---
print_info "Checking if '${PARAM_TO_SET} ${VALUE_TO_SET}' is already active in ${SSH_CONFIG_FILE}..."
# Use awk to find the first uncommented instance and check its value
current_value=$(awk '!/^[[:space:]]*#/ && $1 == "'"${PARAM_TO_SET}"'" { print $2; exit }' "${SSH_CONFIG_FILE}")

if [ "${current_value}" == "${VALUE_TO_SET}" ]; then
    print_success "'${PARAM_TO_SET} ${VALUE_TO_SET}' is already enabled."
    print_info "No changes needed. Exiting."
    exit 0
else
    # Handle case where parameter might be set but to a different value
    if [ -n "${current_value}" ]; then
        print_info "'${PARAM_TO_SET}' found but set to '${current_value}', not '${VALUE_TO_SET}'. Proceeding to enable..."
    else
        print_info "'${PARAM_TO_SET}' not found or not active. Proceeding to enable..."
    fi
fi
echo ""

# --- Step 3: Backup SSH Config ---
print_info "Backing up ${SSH_CONFIG_FILE} to ${BACKUP_FILE}..."
if [ ! -f "$SSH_CONFIG_FILE" ]; then
    print_error "SSH configuration file not found at '${SSH_CONFIG_FILE}'. Aborting."
    exit 1
fi
cp "$SSH_CONFIG_FILE" "$BACKUP_FILE"
if [ $? -ne 0 ]; then
    print_error "Failed to create backup ${BACKUP_FILE}. Aborting."
    exit 1
else
    print_success "Backup created successfully."
fi
echo ""

# --- Step 4: Ensure Setting (Delete existing, Append correct) ---
print_info "Ensuring '${PARAM_TO_SET} ${VALUE_TO_SET}' is set..."
# Pattern to find lines to delete (commented or uncommented, optional leading spaces)
PATTERN_DELETE="^[[:space:]]*#?[[:space:]]*${PARAM_TO_SET}"

print_info "Removing any existing lines for '${PARAM_TO_SET}'..."
# Use a temporary file to safely handle sed and potential errors
temp_sed_out=$(mktemp)
if [ -z "$temp_sed_out" ]; then
    print_error "Failed to create temporary file. Aborting."
    exit 1
fi
# Delete lines matching the pattern, write non-matching lines to temp file
sed -E "/${PATTERN_DELETE}/d" "${SSH_CONFIG_FILE}" > "$temp_sed_out"
sed_exit_code=$?

if [ $sed_exit_code -ne 0 ]; then
    print_error "sed command failed while preparing deletion (Exit code: ${sed_exit_code}). Aborting."
    rm "$temp_sed_out"
    exit 1
fi

# Overwrite the original file with the modified content
mv "$temp_sed_out" "${SSH_CONFIG_FILE}"
if [ $? -ne 0 ]; then
    print_error "Failed to overwrite ${SSH_CONFIG_FILE} after sed deletion step. Restore from backup ${BACKUP_FILE}! Aborting."
    # Note: temp_sed_out might be gone, original is lost if mv failed partially. Backup is critical.
    exit 1
fi
print_info "Existing '${PARAM_TO_SET}' lines removed."

print_info "Appending '${PARAM_TO_SET} ${VALUE_TO_SET}'..."
# Append the desired setting as a new line at the end
if ! printf "%s %s\n" "${PARAM_TO_SET}" "${VALUE_TO_SET}" >> "${SSH_CONFIG_FILE}"; then
     print_error "Failed to append '${PARAM_TO_SET} ${VALUE_TO_SET}' to ${SSH_CONFIG_FILE}. Restore from backup ${BACKUP_FILE}! Aborting."
     exit 1
fi
print_success "'${PARAM_TO_SET} ${VALUE_TO_SET}' appended."
echo ""

# --- Step 5: Restart SSH Service ---
print_info "Attempting to restart the SSH service..."
SERVICE_NAME="sshd" # Most common base name
SERVICE_FILE="${SERVICE_NAME}.service"

# Check common variations
# Use systemctl list-unit-files to check if service exists, more reliable than list-units --all
if ! systemctl list-unit-files --type=service | grep -q -F "${SERVICE_FILE}"; then
    if systemctl list-unit-files --type=service | grep -q -F "ssh.service"; then
        SERVICE_NAME="ssh"
        SERVICE_FILE="ssh.service"
        print_info "Detected SSH service as ${SERVICE_FILE}"
    else
        print_warning "Could not confirm sshd.service or ssh.service existence. Assuming '${SERVICE_FILE}'."
        # Proceed assuming sshd, restart might fail if it's ssh
    fi
fi

print_info "Restarting ${SERVICE_FILE}..."
systemctl restart "${SERVICE_FILE}"
RESTART_STATUS=$?

if [ $RESTART_STATUS -eq 0 ]; then
    print_success "SSH service (${SERVICE_FILE}) restarted successfully."
else
    # Provide more specific troubleshooting commands
    print_error "Failed to restart SSH service (${SERVICE_FILE}). Exit code: ${RESTART_STATUS}."
    print_error "Troubleshooting suggestions:"
    print_error " 1. Check config syntax: sudo sshd -t"
    print_error " 2. Check service status: sudo systemctl status ${SERVICE_FILE}"
    print_error " 3. Check service logs: sudo journalctl -u ${SERVICE_FILE} | tail -n 50"
    print_error "Consider restoring the backup: sudo cp ${BACKUP_FILE} ${SSH_CONFIG_FILE}"
    # Optionally exit here if restart failure is critical
    # exit 1
fi
echo ""

# --- Final Summary ---
print_success "${BOLD}Script finished. '${PARAM_TO_SET} ${VALUE_TO_SET}' should now be configured.${NC}"
print_info "Original config backup: ${BOLD}${BACKUP_FILE}${NC}"
print_info "Verify SSH manually if desired (e.g., 'sudo ssh root@localhost' or check config file)."
echo ""

exit 0
