#!/bin/bash
################################################################################
# Proxmox GPU Passthrough Setup - Main Script
################################################################################
# This script automates the complete setup of NVIDIA GPU passthrough with
# power management for Proxmox VE. It handles IOMMU configuration, driver
# installation, and hook script creation for dynamic GPU switching.
#
# Usage:
#   1. Copy .env.example to .env and configure your values
#   2. Run: ./setup-gpu-passthrough.sh
#
# The setup is divided into phases with reboots between them:
#   Phase 1: System preparation and IOMMU setup
#   Phase 2: NVIDIA driver installation
#   Phase 3: Hook scripts and finalization
################################################################################

set -e

################################################################################
# Colors and Output Functions
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}ℹ️  [INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅ [SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}❌ [ERROR]${NC} $1"
}

print_question() {
    echo -e "${CYAN}❓ [QUESTION]${NC} $1"
}

################################################################################
# Configuration and Validation
################################################################################

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    print_error "Configuration file .env not found!"
    print_info "Please copy .env.example to .env and configure your values:"
    print_info "  cp .env.example .env"
    print_info "  nano .env"
    exit 1
fi

# Source the environment file
source "$ENV_FILE"

# Validate required variables
validate_config() {
    local missing_vars=()
    
    [ -z "$GPU_VGA_PCI_ID" ] && missing_vars+=("GPU_VGA_PCI_ID")
    [ -z "$GPU_AUDIO_PCI_ID" ] && missing_vars+=("GPU_AUDIO_PCI_ID")
    [ -z "$GPU_VGA_DEVICE_ID" ] && missing_vars+=("GPU_VGA_DEVICE_ID")
    [ -z "$GPU_AUDIO_DEVICE_ID" ] && missing_vars+=("GPU_AUDIO_DEVICE_ID")
    [ -z "$VM_ID" ] && missing_vars+=("VM_ID")
    [ -z "$NVIDIA_DRIVER_VERSION" ] && missing_vars+=("NVIDIA_DRIVER_VERSION")
    [ -z "$NVIDIA_DRIVER_URL" ] && missing_vars+=("NVIDIA_DRIVER_URL")
    [ -z "$CPU_VENDOR" ] && missing_vars+=("CPU_VENDOR")
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_error "Missing required configuration variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
    
    # Validate CPU vendor
    if [[ ! "$CPU_VENDOR" =~ ^(intel|amd)$ ]]; then
        print_error "CPU_VENDOR must be 'intel' or 'amd'"
        exit 1
    fi
}

################################################################################
# Phase Tracking
################################################################################

# State file to track setup progress
STATE_FILE="/root/.proxmox-gpu-setup-state"

# Get current phase
get_phase() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "0"
    fi
}

# Set current phase
set_phase() {
    echo "$1" > "$STATE_FILE"
}

# Clear state (for fresh start)
clear_state() {
    rm -f "$STATE_FILE"
}

################################################################################
# Main Setup Functions
################################################################################

# Phase 1: System preparation and IOMMU setup
phase1_system_prep() {
    print_header "🔧 Phase 1: System Preparation and IOMMU Setup"
    
    print_info "Updating system packages..."
    apt update
    apt full-upgrade -y
    print_success "System packages updated"
    
    print_info "Installing prerequisites..."
    apt install -y build-essential dkms pve-headers pkg-config
    
    # Verify kernel headers
    current_kernel=$(uname -r)
    print_info "Current kernel: $current_kernel"
    
    if ! dpkg -l | grep -q "proxmox-headers-$current_kernel"; then
        print_warning "Installing headers for current kernel..."
        apt install -y "proxmox-headers-$current_kernel" || apt install -y pve-headers
    fi
    
    print_success "Prerequisites installed"
    
    # Configure GRUB for IOMMU
    print_info "Configuring GRUB for IOMMU..."
    
    GRUB_FILE="/etc/default/grub"
    GRUB_BACKUP="$GRUB_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Backup GRUB config
    cp "$GRUB_FILE" "$GRUB_BACKUP"
    
    # Determine IOMMU parameters based on CPU vendor
    if [ "$CPU_VENDOR" == "intel" ]; then
        IOMMU_PARAMS="intel_iommu=on iommu=pt"
    else
        IOMMU_PARAMS="amd_iommu=on iommu=pt"
    fi
    
    # Update GRUB_CMDLINE_LINUX_DEFAULT
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE"; then
        # Check if IOMMU params already present
        if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE" | grep -q "iommu"; then
            sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $IOMMU_PARAMS\"/" "$GRUB_FILE"
            print_success "IOMMU parameters added to GRUB"
        else
            print_info "IOMMU parameters already present in GRUB"
        fi
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet $IOMMU_PARAMS\"" >> "$GRUB_FILE"
        print_success "GRUB_CMDLINE_LINUX_DEFAULT created with IOMMU parameters"
    fi
    
    # Update GRUB
    update-grub
    
    # Configure VFIO modules
    print_info "Configuring VFIO modules..."
    
    VFIO_CONF="/etc/modules-load.d/vfio.conf"
    cat > "$VFIO_CONF" << EOF
# VFIO modules for GPU passthrough
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF
    
    print_success "VFIO modules configured"
    
    # Configure driver blacklist
    print_info "Configuring driver blacklist..."
    
    BLACKLIST_FILE="/etc/modprobe.d/blacklist.conf"
    
    # Backup if exists
    if [ -f "$BLACKLIST_FILE" ]; then
        cp "$BLACKLIST_FILE" "$BLACKLIST_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create/update blacklist
    cat > "$BLACKLIST_FILE" << EOF
# Driver blacklist for GPU passthrough
# Generated by proxmox-gpu-setup on $(date)

# Blacklist nouveau (conflicts with NVIDIA driver)
blacklist nouveau

# Blacklist radeon (if not using AMD GPU)
blacklist radeon

# DO NOT blacklist nvidia - we need it for power management!
# The nvidia driver is used when VM is off to enable low power states
EOF
    
    print_success "Driver blacklist configured"
    
    # Disable any existing VFIO auto-binding
    print_info "Checking for existing VFIO auto-binding configuration..."
    
    if [ -f "/etc/modprobe.d/vfio.conf" ]; then
        print_warning "Found /etc/modprobe.d/vfio.conf - disabling for dynamic power management"
        mv /etc/modprobe.d/vfio.conf /etc/modprobe.d/vfio.conf.disabled
        print_info "VFIO auto-binding disabled (allows hook script control)"
    fi
    
    # Update initramfs
    print_info "Updating initramfs..."
    update-initramfs -u
    
    print_success "Phase 1 complete!"
    print_warning "System needs to reboot for IOMMU changes to take effect"
    
    # Set next phase
    set_phase "2"
    
    # Prompt for reboot
    if [ "$AUTO_REBOOT" == "true" ]; then
        print_info "Auto-reboot enabled. Rebooting in 5 seconds..."
        print_info "After reboot, run this script again to continue with Phase 2"
        sleep 5
        reboot
    else
        print_info "Please reboot the system:"
        print_info "  reboot"
        print_info ""
        print_info "After reboot, run this script again to continue with Phase 2"
        exit 0
    fi
}

# Phase 2: NVIDIA driver installation
phase2_nvidia_driver() {
    print_header "🎮 Phase 2: NVIDIA Driver Installation"
    
    # Verify IOMMU is enabled
    print_info "Verifying IOMMU is enabled..."
    
    if dmesg | grep -qi "iommu.*enabled"; then
        print_success "IOMMU is enabled"
        dmesg | grep -i iommu | head -5
    else
        print_error "IOMMU not detected! Check BIOS settings and GRUB configuration"
        exit 1
    fi
    
    # Verify kernel parameters
    print_info "Current kernel parameters:"
    cat /proc/cmdline
    
    # Check GPU visibility
    print_info "Detecting NVIDIA GPU..."
    
    if ! lspci -nn | grep -i nvidia | grep -q "$GPU_VGA_DEVICE_ID"; then
        print_error "GPU not found! Check PCI ID in .env file"
        print_info "Run: lspci -nn | grep -i nvidia"
        exit 1
    fi
    
    print_success "GPU detected:"
    lspci -nn | grep -i nvidia
    
    # Unbind GPU if currently bound
    print_info "Preparing GPU for driver installation..."
    
    if [ -d "/sys/bus/pci/devices/$GPU_VGA_PCI_ID/driver" ]; then
        print_info "Unbinding GPU from current driver..."
        echo "$GPU_VGA_PCI_ID" > /sys/bus/pci/devices/$GPU_VGA_PCI_ID/driver/unbind 2>/dev/null || true
        echo "$GPU_AUDIO_PCI_ID" > /sys/bus/pci/devices/$GPU_AUDIO_PCI_ID/driver/unbind 2>/dev/null || true
    fi
    
    # Clear driver overrides
    if [ -e "/sys/bus/pci/devices/$GPU_VGA_PCI_ID/driver_override" ]; then
        echo "" > /sys/bus/pci/devices/$GPU_VGA_PCI_ID/driver_override 2>/dev/null || true
    fi
    
    # Download NVIDIA driver
    print_info "Downloading NVIDIA driver $NVIDIA_DRIVER_VERSION..."
    
    DRIVER_DIR="/root/nvidia-driver"
    DRIVER_FILE="NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
    DRIVER_PATH="$DRIVER_DIR/$DRIVER_FILE"
    
    mkdir -p "$DRIVER_DIR"
    cd "$DRIVER_DIR"
    
    if [ -f "$DRIVER_PATH" ]; then
        print_info "Driver already downloaded, skipping..."
    else
        if command -v wget &> /dev/null; then
            wget -q --show-progress "$NVIDIA_DRIVER_URL" -O "$DRIVER_PATH"
        elif command -v curl &> /dev/null; then
            curl -L --progress-bar "$NVIDIA_DRIVER_URL" -o "$DRIVER_PATH"
        else
            print_error "Neither wget nor curl available. Install one and try again."
            exit 1
        fi
        
        print_success "Driver downloaded"
    fi
    
    chmod +x "$DRIVER_PATH"
    
    # Install NVIDIA driver
    print_info "Installing NVIDIA driver..."
    print_warning "This may take a few minutes..."
    
    # Determine kernel source path
    KERNEL_VERSION=$(uname -r)
    if [ -d "/lib/modules/$KERNEL_VERSION/build" ]; then
        KERNEL_SOURCE="/lib/modules/$KERNEL_VERSION/build"
    elif [ -d "/usr/src/linux-headers-$KERNEL_VERSION" ]; then
        KERNEL_SOURCE="/usr/src/linux-headers-$KERNEL_VERSION"
    else
        print_error "Cannot find kernel source directory"
        exit 1
    fi
    
    print_info "Using kernel source: $KERNEL_SOURCE"
    echo ""
    
    # Provide clear instructions for interactive prompts
    print_warning "The installer will ask you a few questions:"
    echo ""
    echo "  1. Kernel module type:"
    echo "     → Choose: $NVIDIA_MODULE_TYPE"
    echo ""
    echo "  2. X library path warning (if asked):"
    echo "     → Choose: OK"
    echo ""
    echo "  3. 32-bit compatibility warning (if asked):"
    echo "     → Choose: OK"
    echo ""
    echo "  4. Register kernel module sources with DKMS:"
    echo "     → Choose: Yes"
    echo ""
    echo "  5. Run nvidia-xconfig utility:"
    echo "     → Choose: No"
    echo ""
    print_info "Installation will begin in 5 seconds..."
    sleep 5
    
    # Run installer interactively
    "$DRIVER_PATH" \
        --kernel-source-path="$KERNEL_SOURCE" \
        --dkms \
        --no-x-check
    
    INSTALL_STATUS=$?
    
    if [ $INSTALL_STATUS -ne 0 ]; then
        print_error "Driver installation failed!"
        print_error "Check log: /var/log/nvidia-installer.log"
        print_info "Last 20 lines:"
        tail -n 20 /var/log/nvidia-installer.log
        exit 1
    fi
    
    print_success "NVIDIA driver installed"
    
    # Verify installation
    print_info "Verifying driver installation..."
    
    if command -v nvidia-smi &> /dev/null; then
        print_success "nvidia-smi available"
    else
        print_error "nvidia-smi not found - installation may have failed"
        exit 1
    fi
    
    # Load nvidia module
    print_info "Loading NVIDIA kernel module..."
    modprobe nvidia 2>/dev/null || true
    
    if lsmod | grep -q nvidia; then
        print_success "NVIDIA kernel module loaded"
        lsmod | grep nvidia
    else
        print_warning "NVIDIA module not loaded yet - will load on next boot"
    fi
    
    print_success "Phase 2 complete!"
    
    # Set next phase
    set_phase "3"
    
    print_info "Continue to Phase 3: Hook scripts and finalization"
    print_info "No reboot needed. Press Enter to continue..."
    read
}

# Phase 3: Hook scripts and finalization
phase3_finalization() {
    print_header "✨ Phase 3: Hook Scripts and Finalization"
    
    # Bind GPU to nvidia driver first
    print_info "Binding GPU to NVIDIA driver..."
    
    # Unbind if currently bound
    if [ -d "/sys/bus/pci/devices/$GPU_VGA_PCI_ID/driver" ]; then
        echo "$GPU_VGA_PCI_ID" > /sys/bus/pci/devices/$GPU_VGA_PCI_ID/driver/unbind 2>/dev/null || true
    fi
    
    # Bind to nvidia
    echo "nvidia" > /sys/bus/pci/devices/$GPU_VGA_PCI_ID/driver_override
    echo "$GPU_VGA_PCI_ID" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || true
    
    sleep 2
    
    # Test nvidia-smi
    print_info "Testing NVIDIA driver..."
    
    if nvidia-smi &> /dev/null; then
        print_success "NVIDIA driver working!"
        nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
    else
        print_error "nvidia-smi failed - driver may not be working correctly"
        exit 1
    fi
    
    # Configure persistence daemon
    print_info "Configuring NVIDIA persistence daemon..."
    
    PERSISTENCED_SERVICE="/etc/systemd/system/nvidia-persistenced.service"
    
    cat > "$PERSISTENCED_SERVICE" << 'PERSISTEOF'
[Unit]
Description=NVIDIA Persistence Daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/nvidia-persistenced --user root --no-persistence-mode
ExecStop=/usr/bin/nvidia-persistenced --terminate
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
PERSISTEOF
    
    systemctl daemon-reload
    systemctl enable nvidia-persistenced
    systemctl start nvidia-persistenced
    
    if systemctl is-active --quiet nvidia-persistenced; then
        print_success "NVIDIA persistence daemon running"
    else
        print_warning "Persistence daemon may not be running correctly"
    fi
    
    # Create GPU initialization script
    print_info "Creating GPU initialization script..."
    
    GPU_INIT_SCRIPT="/usr/local/bin/nvidia-gpu-init.sh"
    
    cat > "$GPU_INIT_SCRIPT" << INITEOF
#!/bin/bash
################################################################################
# NVIDIA GPU Initialization on Boot
# Ensures GPU is bound to nvidia driver with persistence mode enabled
################################################################################

GPU_VGA="$GPU_VGA_PCI_ID"
GPU_AUDIO="$GPU_AUDIO_PCI_ID"

# Wait for system to settle
sleep 5

logger "nvidia-gpu-init: Starting GPU initialization"

# Check if already bound to nvidia
if [ -e "/sys/bus/pci/devices/\$GPU_VGA/driver" ]; then
    CURRENT_DRIVER=\$(readlink /sys/bus/pci/devices/\$GPU_VGA/driver | awk -F'/' '{print \$NF}')
    
    if [ "\$CURRENT_DRIVER" == "nvidia" ]; then
        logger "nvidia-gpu-init: GPU already on nvidia driver"
        /usr/bin/nvidia-smi -pm 1
        exit 0
    fi
    
    # Unbind from current driver
    logger "nvidia-gpu-init: Unbinding from \$CURRENT_DRIVER"
    echo "\$GPU_VGA" > /sys/bus/pci/devices/\$GPU_VGA/driver/unbind 2>/dev/null || true
    echo "\$GPU_AUDIO" > /sys/bus/pci/devices/\$GPU_AUDIO/driver/unbind 2>/dev/null || true
fi

# Bind to nvidia driver
logger "nvidia-gpu-init: Binding to nvidia driver"
echo "nvidia" > /sys/bus/pci/devices/\$GPU_VGA/driver_override
echo "\$GPU_VGA" > /sys/bus/pci/drivers/nvidia/bind

# Wait and enable persistence
sleep 2
/usr/bin/nvidia-smi -pm 1

logger "nvidia-gpu-init: GPU initialization complete"
exit 0
INITEOF
    
    chmod +x "$GPU_INIT_SCRIPT"
    print_success "GPU initialization script created"
    
    # Create systemd service for GPU init
    print_info "Creating GPU initialization service..."
    
    GPU_INIT_SERVICE="/etc/systemd/system/nvidia-gpu-init.service"
    
    cat > "$GPU_INIT_SERVICE" << 'INITSERVEOF'
[Unit]
Description=NVIDIA GPU Initialization on Boot
After=nvidia-persistenced.service
Requires=nvidia-persistenced.service
Before=pve-guests.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nvidia-gpu-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
INITSERVEOF
    
    systemctl daemon-reload
    systemctl enable nvidia-gpu-init.service
    
    print_success "GPU initialization service created and enabled"
    
    # Create hook script directory
    print_info "Creating hook script..."
    
    HOOK_DIR="/var/lib/vz/snippets"
    mkdir -p "$HOOK_DIR"
    chmod 755 "$HOOK_DIR"
    
    HOOK_SCRIPT="$HOOK_DIR/gpu-${VM_ID}-hook.sh"
    
    cat > "$HOOK_SCRIPT" << HOOKEOF
#!/usr/bin/env bash
################################################################################
# GPU Passthrough Hook for VM $VM_ID
# Automatically manages GPU binding during VM lifecycle
#
# This script is called by Proxmox at different VM lifecycle events:
#   - pre-start:  Before VM starts (bind GPU to vfio-pci)
#   - post-stop:  After VM stops (return GPU to nvidia driver)
################################################################################

GPU_VGA="$GPU_VGA_PCI_ID"
GPU_AUDIO="$GPU_AUDIO_PCI_ID"

log() {
    logger "GPU Hook [\$2]: \$1"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [GPU Hook] [\$2] \$1"
}

unbind_device() {
    local dev="\$1"
    local label="\$2"
    if [ -e /sys/bus/pci/devices/\$dev/driver ]; then
        local current=\$(readlink /sys/bus/pci/devices/\$dev/driver | awk -F/ '{print \$NF}')
        log "Unbinding \$label (\$dev) from \$current" "\$3"
        echo "\$dev" > /sys/bus/pci/devices/\$dev/driver/unbind
        log "Unbound \$label successfully" "\$3"
    else
        log "No driver bound to \$label (\$dev), skipping unbind" "\$3"
    fi
}

if [ "\$2" == "pre-start" ]; then
    ############################################################################
    # VM Starting: Bind GPU to vfio-pci for passthrough
    ############################################################################

    log "VM \$1 starting - preparing GPU for passthrough" "\$2"

    # Disable persistence mode to allow unbinding
    log "Disabling nvidia persistence mode" "\$2"
    if nvidia-smi -pm 0; then
        log "Persistence mode disabled" "\$2"
    else
        log "WARNING: Failed to disable persistence mode - unbind may fail" "\$2"
    fi

    # Unbind both devices from whatever driver currently holds them
    unbind_device "\$GPU_VGA"   "GPU VGA"   "\$2"
    unbind_device "\$GPU_AUDIO" "GPU Audio" "\$2"

    # Set driver override to vfio-pci
    log "Setting driver override to vfio-pci" "\$2"
    echo vfio-pci > /sys/bus/pci/devices/\$GPU_VGA/driver_override
    echo vfio-pci > /sys/bus/pci/devices/\$GPU_AUDIO/driver_override

    # Bind to vfio-pci
    log "Binding GPU VGA to vfio-pci" "\$2"
    echo "\$GPU_VGA" > /sys/bus/pci/drivers/vfio-pci/bind
    log "Binding GPU Audio to vfio-pci" "\$2"
    echo "\$GPU_AUDIO" > /sys/bus/pci/drivers/vfio-pci/bind

    log "GPU VGA driver:   \$(readlink /sys/bus/pci/devices/\$GPU_VGA/driver   | awk -F/ '{print \$NF}')" "\$2"
    log "GPU Audio driver: \$(readlink /sys/bus/pci/devices/\$GPU_AUDIO/driver | awk -F/ '{print \$NF}')" "\$2"
    log "GPU ready for passthrough to VM \$1" "\$2"

elif [ "\$2" == "post-stop" ]; then
    ############################################################################
    # VM Stopped: Return GPU to nvidia driver for power management
    ############################################################################

    log "VM \$1 stopped - returning GPU to nvidia driver" "\$2"

    # Unbind both devices from vfio-pci
    unbind_device "\$GPU_VGA"   "GPU VGA"   "\$2"
    unbind_device "\$GPU_AUDIO" "GPU Audio" "\$2"

    # Set driver override to nvidia for VGA, clear for audio
    log "Setting driver overrides" "\$2"
    echo nvidia > /sys/bus/pci/devices/\$GPU_VGA/driver_override
    echo ""      > /sys/bus/pci/devices/\$GPU_AUDIO/driver_override

    # Ensure nvidia module is loaded
    log "Loading nvidia module" "\$2"
    modprobe nvidia

    # Bind VGA to nvidia
    log "Binding GPU VGA to nvidia" "\$2"
    echo "\$GPU_VGA" > /sys/bus/pci/drivers/nvidia/bind

    # Re-enable persistence mode for low power state
    sleep 1
    log "Enabling persistence mode" "\$2"
    nvidia-smi -pm 1

    log "GPU VGA driver: \$(readlink /sys/bus/pci/devices/\$GPU_VGA/driver | awk -F/ '{print \$NF}')" "\$2"
    log "GPU returned to nvidia driver with persistence mode enabled" "\$2"
fi

exit 0
HOOKEOF
    
    chmod +x "$HOOK_SCRIPT"
    print_success "Hook script created: $HOOK_SCRIPT"
    
    # Update VM configuration
    print_info "Updating VM $VM_ID configuration..."
    
    VM_CONF="/etc/pve/qemu-server/${VM_ID}.conf"
    
    if [ ! -f "$VM_CONF" ]; then
        print_warning "VM $VM_ID configuration not found at $VM_CONF"
        print_warning "You'll need to:"
        print_warning "  1. Create/restore VM $VM_ID"
        print_warning "  2. Add GPU via web UI (Hardware → Add PCI Device)"
        print_warning "  3. Add this line to VM config:"
        print_warning "     hookscript: local:snippets/gpu-${VM_ID}-hook.sh"
    else
        # Backup VM config
        cp "$VM_CONF" "${VM_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Add hookscript if not present
        if grep -q "^hookscript:" "$VM_CONF"; then
            print_info "Hook script entry already exists in VM config"
        else
            echo "hookscript: local:snippets/gpu-${VM_ID}-hook.sh" >> "$VM_CONF"
            print_success "Hook script added to VM $VM_ID configuration"
        fi
        
        # Check for GPU passthrough configuration
        if grep -q "^hostpci.*$GPU_VGA_PCI_ID" "$VM_CONF"; then
            print_success "GPU passthrough already configured in VM"
        else
            print_warning "GPU passthrough not found in VM config"
            print_info "Add GPU via Proxmox web UI:"
            print_info "  VM $VM_ID → Hardware → Add → PCI Device"
            print_info "  Select GPU, check 'All Functions' and 'PCI-Express'"
        fi
    fi
    
    # Enable persistence mode now
    print_info "Enabling persistence mode..."
    nvidia-smi -pm 1
    
    # Final status check
    print_info "Current GPU status:"
    nvidia-smi --query-gpu=name,pstate,power.draw,persistence_mode --format=csv,noheader
    
    print_success "Phase 3 complete!"
    
    # Clear state - setup is done
    clear_state
    
    # Final summary
    print_header "🎉 Setup Complete!"
    
    echo ""
    print_success "GPU passthrough with power management is now configured!"
    echo ""
    print_info "📋 Configuration Summary:"
    echo "  🎮 GPU: $GPU_VGA_PCI_ID"
    echo "  💻 VM ID: $VM_ID"
    echo "  🔧 Driver: NVIDIA $NVIDIA_DRIVER_VERSION"
    echo "  📜 Hook script: $HOOK_SCRIPT"
    echo ""
    
    print_header "📝 Manual Steps Required"
    
    echo ""
    print_info "🔧 Step 1: Add GPU to VM (via Proxmox Web UI)"
    echo "  1. Go to VM $VM_ID → Hardware → Add → PCI Device"
    echo "  2. Select GPU: $GPU_VGA_PCI_ID"
    echo "  3. ✅ Check 'All Functions' (includes audio)"
    echo "  4. ✅ Check 'PCI-Express'"
    echo "  5. Click Add"
    echo ""
    
    print_info "📜 Step 2: Verify Hook Script is Configured"
    echo "  Check VM config:"
    echo "    cat /etc/pve/qemu-server/${VM_ID}.conf | grep hookscript"
    echo ""
    echo "  Should show:"
    echo "    hookscript: local:snippets/gpu-${VM_ID}-hook.sh"
    echo ""
    echo "  If missing, add it:"
    echo "    echo 'hookscript: local:snippets/gpu-${VM_ID}-hook.sh' >> /etc/pve/qemu-server/${VM_ID}.conf"
    echo ""
    
    if [ -n "${STORAGE_DRIVE_1:-}" ] || [ -n "${STORAGE_DRIVE_2:-}" ]; then
        print_info "💾 Step 3: Attach Storage Drives to VM (Optional)"
        [ -n "${STORAGE_DRIVE_1:-}" ] && echo "  qm set $VM_ID -sata0 $STORAGE_DRIVE_1"
        [ -n "${STORAGE_DRIVE_2:-}" ] && echo "  qm set $VM_ID -sata1 $STORAGE_DRIVE_2"
        echo ""
    fi
    
    print_header "🔄 Next Steps"
    
    echo ""
    print_info "1️⃣  Reboot the system:"
    echo "     reboot"
    echo ""
    print_info "2️⃣  After reboot, verify GPU is in P8 low power state:"
    echo "     nvidia-smi"
    echo "     # Should show P8 state, 5-15W power draw"
    echo ""
    print_info "3️⃣  Test VM start/stop cycle:"
    echo "     qm start $VM_ID"
    echo "     # GPU should switch to vfio-pci"
    echo ""
    echo "     qm stop $VM_ID"
    echo "     # GPU should return to nvidia driver and P8 state"
    echo ""
    
    print_header "🔍 Monitoring & Troubleshooting"
    
    echo ""
    print_info "📊 Real-time GPU status:"
    echo "     watch -n 1 'nvidia-smi'"
    echo ""
    print_info "🔌 Check GPU driver binding:"
    echo "     lspci -nnk -s ${GPU_VGA_PCI_ID#0000:}"
    echo ""
    print_info "📋 Monitor hook script logs:"
    echo "     journalctl -f | grep 'GPU Hook'"
    echo ""
    print_info "🧪 Test hook script manually:"
    echo "     # Simulate post-stop (return GPU to host)"
    echo "     /var/lib/vz/snippets/gpu-${VM_ID}-hook.sh $VM_ID post-stop"
    echo ""
    print_info "🔧 If GPU doesn't return to host after VM shutdown:"
    echo "     # Manually bind GPU back to nvidia:"
    echo "     echo '$GPU_VGA_PCI_ID' > /sys/bus/pci/devices/$GPU_VGA_PCI_ID/driver/unbind"
    echo "     echo 'nvidia' > /sys/bus/pci/devices/$GPU_VGA_PCI_ID/driver_override"
    echo "     echo '$GPU_VGA_PCI_ID' > /sys/bus/pci/drivers/nvidia/bind"
    echo "     nvidia-smi -pm 1"
    echo ""
    
    if [ "$AUTO_REBOOT" == "true" ]; then
        print_warning "⏰ Auto-reboot enabled. Rebooting in 10 seconds..."
        sleep 10
        reboot
    else
        print_info "♻️  Please reboot to complete setup: reboot"
    fi
}

################################################################################
# Main Execution
################################################################################

# Validate configuration
validate_config

# Get current phase
CURRENT_PHASE=$(get_phase)

print_header "🚀 Proxmox GPU Passthrough Setup"
print_info "📄 Configuration loaded from: $ENV_FILE"
print_info "🔢 Current phase: $CURRENT_PHASE"

case $CURRENT_PHASE in
    0)
        phase1_system_prep
        ;;
    1)
        phase1_system_prep
        ;;
    2)
        phase2_nvidia_driver
        phase3_finalization
        ;;
    3)
        phase3_finalization
        ;;
    *)
        print_error "Unknown phase: $CURRENT_PHASE"
        print_info "To restart setup from beginning, run:"
        print_info "  rm $STATE_FILE"
        exit 1
        ;;
esac