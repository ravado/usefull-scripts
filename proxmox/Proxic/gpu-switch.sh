#!/usr/bin/env bash
################################################################################
# GPU Switch - Manual GPU passthrough control
#
# Usage:
#   ./gpu-switch.sh pre-start   # Switch GPU to vfio-pci (ready for VM)
#   ./gpu-switch.sh post-stop   # Return GPU to nvidia driver (host power mgmt)
#   ./gpu-switch.sh status      # Show current GPU driver state
################################################################################

set -e

GPU_VGA="0000:01:00.0"
GPU_AUDIO="0000:01:00.1"

################################################################################
# Helpers
################################################################################

log() {
    logger "GPU Switch: $1" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [GPU Switch] $1"
}

unbind_device() {
    local dev="$1"
    local label="$2"
    if [ -e /sys/bus/pci/devices/$dev/driver ]; then
        local current=$(readlink /sys/bus/pci/devices/$dev/driver | awk -F/ '{print $NF}')
        log "Unbinding $label ($dev) from $current"
        echo "$dev" > /sys/bus/pci/devices/$dev/driver/unbind
        log "Unbound $label successfully"
    else
        log "No driver bound to $label ($dev), skipping unbind"
    fi
}

status() {
    echo ""
    echo "=== GPU Driver Status ==="
    lspci -nnk -s ${GPU_VGA#0000:}
    echo "---"
    lspci -nnk -s ${GPU_AUDIO#0000:}
    echo ""
    if [ -e /sys/bus/pci/devices/$GPU_VGA/driver ]; then
        local drv=$(readlink /sys/bus/pci/devices/$GPU_VGA/driver | awk -F/ '{print $NF}')
        echo "GPU VGA is on: $drv"
        if [ "$drv" == "nvidia" ]; then
            echo ""
            nvidia-smi --query-gpu=name,pstate,power.draw,persistence_mode --format=csv,noheader 2>/dev/null || true
        fi
    else
        echo "GPU VGA has no driver bound"
    fi
    echo ""
}

################################################################################
# Commands
################################################################################

case "$1" in

    pre-start)
        log "--- pre-start: switching GPU to vfio-pci ---"

        log "Disabling nvidia persistence mode"
        if nvidia-smi -pm 0; then
            log "Persistence mode disabled"
        else
            log "WARNING: Failed to disable persistence mode - unbind may fail"
        fi

        unbind_device "$GPU_VGA"   "GPU VGA"
        unbind_device "$GPU_AUDIO" "GPU Audio"

        log "Setting driver override to vfio-pci"
        echo vfio-pci > /sys/bus/pci/devices/$GPU_VGA/driver_override
        echo vfio-pci > /sys/bus/pci/devices/$GPU_AUDIO/driver_override

        log "Binding GPU VGA to vfio-pci"
        echo "$GPU_VGA" > /sys/bus/pci/drivers/vfio-pci/bind
        log "Binding GPU Audio to vfio-pci"
        echo "$GPU_AUDIO" > /sys/bus/pci/drivers/vfio-pci/bind

        log "GPU VGA driver:   $(readlink /sys/bus/pci/devices/$GPU_VGA/driver   | awk -F/ '{print $NF}')"
        log "GPU Audio driver: $(readlink /sys/bus/pci/devices/$GPU_AUDIO/driver | awk -F/ '{print $NF}')"
        log "--- pre-start complete: GPU ready for passthrough ---"
        ;;

    post-stop)
        log "--- post-stop: returning GPU to nvidia ---"

        unbind_device "$GPU_VGA"   "GPU VGA"
        unbind_device "$GPU_AUDIO" "GPU Audio"

        log "Setting driver overrides"
        echo nvidia > /sys/bus/pci/devices/$GPU_VGA/driver_override
        echo ""      > /sys/bus/pci/devices/$GPU_AUDIO/driver_override

        log "Loading nvidia module"
        modprobe nvidia

        log "Binding GPU VGA to nvidia"
        echo "$GPU_VGA" > /sys/bus/pci/drivers/nvidia/bind

        sleep 1
        log "Enabling persistence mode"
        nvidia-smi -pm 1

        log "GPU VGA driver: $(readlink /sys/bus/pci/devices/$GPU_VGA/driver | awk -F/ '{print $NF}')"
        log "--- post-stop complete: GPU returned to host ---"
        ;;

    status)
        status
        ;;

    *)
        echo "Usage: $0 {pre-start|post-stop|status}"
        exit 1
        ;;
esac
