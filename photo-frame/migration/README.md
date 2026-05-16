# PicFrame Setup & Backup Scripts

```
  ⚔️  PicFrame Migration Toolkit  ⚔️
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  Raspberry Pi  ·  Wayland/labwc  ·  venv
```

Scripts for installing, backing up, and restoring PicFrame on Raspberry Pi.
**Tested on:** PiOS 64-bit (Debian Trixie) · Raspberry Pi Zero 2W

---

## Quick Start

1. Flash **PiOS 64-bit (Debian Trixie)** to SD card, boot, connect to WiFi, SSH in
2. Run the [one-liner](#one-liner-install) to download all scripts
3. Edit `backup.env` with your SMB credentials
4. Run scripts in order: `./1_install_packages.sh` → `./2_install_picframe.sh` → `./3_restore_samba.sh` → `./4_restore_picframe_backup.sh` → `./5_configure_photo_sync.sh`
5. Manually apply `configuration.yaml` (paths changed from old install)

---

## Scripts

| # | Script | Purpose |
|---|--------|---------|
| 0 | `0_backup_setup.sh` | Archive config to SMB share |
| 1 | `1_install_packages.sh` | System packages (libsdl2, labwc, wireguard, rclone...) |
| 2 | `2_install_picframe.sh` | PicFrame dev fork into venv + Wayland + systemd service |
| 3 | `3_restore_samba.sh` | Restore SMB server & client credentials |
| 4 | `4_restore_picframe_backup.sh` | Restore SSH, WireGuard, crontab, picframe_data |
| 5 | `5_configure_photo_sync.sh` | *(optional)* rclone sync from NAS + daily cron |

> Run in order: `1` → `2` → `3` → `4` → `5`
> `configuration.yaml` and `picframe.service` are **not** auto-restored — apply manually.

---

## Configuration

Secrets live in `backup.env` (not committed):

```ini
USERNAME="your_samba_username"
PASSWORD="your_samba_password"
SMB_CRED_USER="your_client_user"
SMB_CRED_PASS="your_client_pass"
```

---

## Networking Notes

PiOS Trixie's network stack stays as-is — **NetworkManager** handles WiFi/DHCP. We do **not** switch to `systemd-networkd` or `dhcpcd`.

The only network-related package added specifically for WireGuard is **`openresolv`** (line 52 of `1_install_packages.sh`). Reason:

- `wg-quick up wg0` calls `/sbin/resolvconf` to push tunnel DNS settings into the system resolver
- On Trixie the older `resolvconf` package is gone; `openresolv` provides a drop-in `/sbin/resolvconf` binary
- Without it, the tunnel either won't come up or won't resolve names through it

If WireGuard DNS issues arise, verify in this order:
```bash
which resolvconf                 # should exist (from openresolv)
sudo wg show                     # tunnel active?
sudo systemctl status wg-quick@wg0
cat /etc/resolv.conf             # tunnel DNS should appear when wg0 up
```

---

## One-Liner Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ravado/usefull-scripts/main/photo-frame/migration/install_all.sh)
```

---

## Prefixes (multi-frame support)

```bash
# 🏠 backup
./0_backup_setup.sh home
./0_backup_setup.sh batanovs

# 🔄 restore by prefix
./4_restore_picframe_backup.sh home latest

# 📦 restore by exact archive
./4_restore_picframe_backup.sh home picframe_home_setup_backup_20250802_104025.tar.gz
```
