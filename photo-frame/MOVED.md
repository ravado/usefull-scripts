# photo-frame/ has moved

These scripts are now maintained inside the picframe fork itself:

**New home:** https://github.com/ravado/picframe/tree/main/scripts

This includes:

- `migration/` — install chain (`install_all.sh`, `1_install_packages.sh` … `5_configure_photo_sync.sh`, sudoers helpers)
- `monitoring/` — fluent-bit / node_exporter / alloy log-and-metrics shippers (formerly `logs-and-monitoring/`)
- `photo-normalization/` — EXIF rotation, resizing, and related utilities
- `grafana-dashboards/` — exported dashboard JSON
- All loose ops scripts (sensor readers, MQTT helpers, photo utilities, aliases, `monitor_control.sh`, etc.)

## Install one-liner (new location)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ravado/picframe/main/scripts/migration/install_all.sh)
```

The `2_install_picframe.sh` step clones the picframe fork to `~/picframe`, so all scripts under `~/picframe/scripts/` are then available locally on each frame. The previous clone of `usefull-scripts` into `~/Documents/Scripts/` is no longer needed.
