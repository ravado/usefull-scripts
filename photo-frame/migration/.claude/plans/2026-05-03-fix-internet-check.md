# Fix Internet Connectivity Check in 2_install_picframe.sh

## Goal
Stop the script from hanging forever on "No internet connection. Retrying in 5 seconds..." by making the check robust and bounded.

## Problem
- `ping google.com` requires DNS — fails if DNS isn't ready (common after reboot on Pi Zero 2W)
- No max retry limit — infinite loop if network never comes up
- Systemd resume service has no `After=network-online.target` — starts before network is ready

## Steps
- [ ] Change `check_internet_connection()` to ping an IP address (`1.1.1.1`) instead of `google.com` to remove DNS dependency
- [ ] Add a secondary DNS check (ping `google.com`) after IP connectivity is confirmed, so we know DNS works before apt/git/pip
- [ ] Add max retry count (60 attempts = 5 minutes) with a clear failure message instead of infinite loop
- [ ] Add `After=network-online.target` and `Wants=network-online.target` to the systemd resume service (line 45)
- [ ] Increase ping timeout from `-W 1` to `-W 3` for flaky WiFi

## Rollback
Revert the single function and the systemd service template — changes are localized to `check_internet_connection()` and `add_systemd_service()`.
