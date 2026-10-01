#!/bin/bash

. /lib/dracut-lib.sh
export CMDLINE=$(cat /proc/cmdline )
root=$(dracut-getarg root)

if [ ${root:0:5} == "LABEL" ]; then
  cancel_wait_for_dev /dev/disk/by-label/${root:6}
else
  cancel_wait_for_dev $root
fi
