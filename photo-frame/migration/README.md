# PicFrame Setup & Backup Scripts

```
  ⚔️  PicFrame Migration Toolkit  ⚔️
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  Raspberry Pi  ·  Wayland/labwc  ·  venv
```

Scripts for installing, backing up, and restoring PicFrame on Raspberry Pi (Debian-based).

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
