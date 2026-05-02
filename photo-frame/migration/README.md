# 📂 PicFrame Setup & Backup Scripts

This repository contains scripts for setting up, backing up, and restoring PicFrame photo frame environments on Raspberry Pi or Debian-based systems.  
It also includes automatic SMB backup integration and environment-based configuration.

---

## 📜 Scripts Overview

### `0_backup_setup.sh`
- Creates a timestamped backup and places an archive on the SMB share.

### `1_install_packages.sh`
- Installs all required system packages (libsdl2, labwc, wireguard, rclone, samba, etc.).
- **Run this before** `1_install_picframe_developer_mode.sh`.

### `1_install_picframe_developer_mode.sh`
- Installs PicFrame (developer fork) and all dependencies into a Python venv.
- Sets up Wayland/labwc display stack, systemd user service, sudoers rules.
- **Requires:** `1_install_packages.sh` to be run first.

### `2_restore_samba.sh`
- Restores SMB credentials for both server and client.
- **Requires:** `backup.env` file with credentials located next to the script.

### `3_restore_picframe_backup.sh`
- Restores a backup created by `0_backup_setup.sh`.
- Restores SSH keys, WireGuard config, git config, crontab, and picframe_data.
- Does **not** restore `configuration.yaml` or `picframe.service` — apply those manually.

### `5_configure_photo_sync.sh`
- *(Optional)* Configures automatic photo sync from NAS via `rclone` (SMB remote).
- Creates a systemd template unit `photo-sync@<instance>` and a daily cron job.

---

## ⚙️ Configuration

Secrets and credentials are stored in a separate `.env` file placed next to the script  
(for example, `backup.env` for `2_restore_samba.sh`):

```ini
USERNAME="your_samba_username"
PASSWORD="your_samba_password"
SMB_CRED_USER="your_client_user"
SMB_CRED_PASS="your_client_pass"
...
```


## 🏃 One-Liner Installer & Runner

To download all scripts, ensure environment loading is set up, and run each script interactively with confirmation:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ravado/usefull-scripts/main/photo-frame/migration/install_all.sh)
```

## 📌 Prefixes and Backup Names

**Use a prefix** to distinguish between multiple PicFrame devices:
```bash
./0_backup_setup.sh home
./0_backup_setup.sh batanovs
```

**Restore by prefix**:
```bash
./3_restore_picframe_backup.sh home latest
./3_restore_picframe_backup.sh batanovs latest
```

**Restore by exact filename**:
```bash
./3_restore_picframe_backup.sh home picframe_home_setup_backup_20250802_104025.tar.gz
```