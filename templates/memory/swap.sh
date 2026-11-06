#!/vendor/bin/sh
# Swap for this 1 GB unit (docs/17): zram fills first because it's much faster, then a 2 GiB file on /data takes the overflow.
# /data isn't encrypted on this build, so swapping to a file there works. It uses eMMC write cycles when it's in use.
log() { echo "hermes_swap: $1" > /dev/kmsg; }
echo 100 > /proc/sys/vm/swappiness
echo 0 > /proc/sys/vm/page-cluster

if ! grep -q zram0 /proc/swaps; then
    echo lz4 > /sys/block/zram0/comp_algorithm
    echo 536870912 > /sys/block/zram0/disksize
    mkswap /dev/block/zram0 > /dev/null && swapon -p 100 /dev/block/zram0 && log "zram on" || log "zram failed"
fi

# This service can start before init has created /data/vendor.
i=0
while [ ! -d /data/vendor ] && [ "$i" -lt 60 ]; do
    sleep 1
    i=$((i + 1))
done

F=/data/vendor/hermes_swapfile
# One byte under 2 GiB: toybox fallocate rejects anything over 2147483647.
SIZE=2147483647
if [ "$(stat -c %s $F 2>/dev/null)" != "$SIZE" ]; then
    rm -f $F
    if ! fallocate -l $SIZE $F 2> /dev/kmsg; then
        log "can't allocate $F"
        rm -f $F
        exit 0
    fi
    chmod 600 $F
    mkswap $F > /dev/null 2> /dev/kmsg || { log "mkswap failed"; rm -f $F; exit 0; }
fi
swapon -p 10 $F 2> /dev/kmsg && log "file on" || log "swapon failed"
