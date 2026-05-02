# Extract Package Installation into 1_install_packages.sh

## Goal
Extract the system package installation steps (apt) from `1_install_picframe_developer_mode.sh` into a new standalone `1_install_packages.sh`, and remove those steps from the developer mode script.

## Source
`1_install_picframe_developer_mode.sh` Step 3 and Step 4:
- Step 3: `sudo apt-get install -y samba`
- Step 4: `sudo apt-get install -y git libsdl2-* xwayland labwc wlr-randr vlc ffmpeg imagemagick wireguard rsync smbclient rclone inotify-tools libgpiod2 bc btop locales resolvconf mosquitto mosquitto-clients`

## Steps

- [ ] Create `1_install_packages.sh`:
  - Header with `set -euo pipefail` and emoji-style logging
  - `apt-get update` + `apt upgrade`
  - Combined `apt-get install` with all packages from Steps 3 and 4 merged
  - Internet connectivity check before installing (reuse pattern from developer mode script)

- [ ] Edit `1_install_picframe_developer_mode.sh`:
  - Add note at top: "Run 1_install_packages.sh before this script"
  - Remove Step 3 (samba install)
  - Remove Step 4 (additional packages + mkdir)
  - Renumber remaining steps: 5→3, 6→4, 7→5, 8→6, 9→7
  - Update all `update_progress N` calls and `if [ "$LAST_COMPLETED_STEP" -lt N ]` conditions
  - Update final `ge 9` check to `ge 7`

- [ ] `1_install_picframe.sh` — no changes

## Rollback
`git checkout 1_install_picframe_developer_mode.sh` and delete `1_install_packages.sh`.
