#!/bin/sh

. /lib/dracut-lib.sh

_img="/local/conda/images/python-nest.squashfs"
_mountpoint="/local/conda/envs/python-nest"

[ -r "$_img" ] || die "Missing Conda squashfs image: $_img"

mkdir -p "$_mountpoint"

if grep -qs "[[:space:]]$_mountpoint[[:space:]]" /proc/mounts; then
    return 0 2>/dev/null || exit 0
fi

modprobe loop 2>/dev/null || :
modprobe squashfs 2>/dev/null || :

mount -t squashfs -o ro,loop "$_img" "$_mountpoint" \
    || die "Could not mount $_img on $_mountpoint"

info "Mounted $_img on $_mountpoint"
