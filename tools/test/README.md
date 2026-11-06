# Testing the backup tool without a device

`fake-adb.example.txt` is the stub used to test `20-backup.sh`: it answers adb commands from a fake disk in a directory. To use it, build a fake tree with `dev/block`, `sys/class/block` and `proc/partitions`, set `F=` at the top, then run `ADB=/path/to/fake-adb 20-backup.sh out/`. Set `CORRUPT=1` to truncate one transfer and confirm the retry works. Regular files aren't block devices, so `mmcblkNbootN` isn't copied in this setup.

If you change `20-backup.sh`, retest: the first run here found a real bug, where finding no partitions still reported success.
