#!/bin/bash

# 2023, Geert Geurts <geert@verweggistan.eu>
# SPDX-License-Identifier: BSD

# called by dracut
check() {
  require_binaries dirname date|| return 1
  # 0 enables by default, 255 only on request
  return 255
}

# called by dracut
depends() {
  echo "sshd"
}

# called by dracut
install() {

  if [ ! -f "${moddir}/tuxifier-python.squashfs" ]; then
    dfatal "Missing ${moddir}/tuxifier-python.squashfs. See dracut-tuxifier/conda-recipes/tuxifier-python.yml"
    return 1
  fi
  # dirname is needed for conda/bin/activate... Not required but useful for debugging
  inst /usr/bin/dirname
  inst chmod
  inst date
  inst ldconfig # required for library resolution python ctypes.util

  # glibc installation
  #   glibc core
  inst_libdir_file \
    'ld-linux*.so.*' \
    'ld-*.so.*' \
    'libc.so.*' \
    'libm.so.*' \
    'libresolv.so.*'
  # glibc compatible
  inst_libdir_file \
    'libdl.so.*' \
    'libpthread.so.*' \
    'librt.so.*' \
    'libutil.so.*' \
    'libanl.so.*' \
    'libBrokenLocale.so.*' \
    'libthread_db.so.*'
  # glibc runtime
  inst_libdir_file \
    'libnss_*.so.*' \
    'gconv/*.so' \
    'gconv/gconv-modules' \
    'gconv/gconv-modules.cache'

  # add root entry to shadow when not there (f44)
  if ! grep -qs '^root:' "$initdir/etc/shadow"; then
    dinfo "Add shadow entry for root"
    echo "root:*:::::::" >> "$initdir/etc/shadow"
  fi
  # Add mount hook and install tuxifier-python.squashfs
  mkdir -p "${initdir}/local/conda/images"
  mkdir -p "${initdir}/local/conda/envs/tuxifier-python"
  inst /etc/nsswitch.conf

  inst "${moddir}/tuxifier-python.squashfs" "/local/conda/images/tuxifier-python.squashfs"
  inst_hook initqueue 50 "$moddir/mount-conda-squashfs.sh"

  # wait_for_ansible after python is mounted
  inst_hook pre-mount 95 "$moddir/wait_for_ansible_finished.sh"

  # umount tuxifier-python.squashfs
  inst_hook cleanup 05 "$moddir/umount-tuxifier-python.sh"

  # check if internal-sftp is enabled otherwise enable it here
  if ! grep -q internal-sftp "${initdir}"/etc/ssh/sshd_config; then
    mv "${initdir}/etc/ssh/sshd_config" "${initdir}/etc/ssh/sshd_config.bak"
    awk '!found && /^AcceptEnv/ { print "Subsystem sftp                  internal-sftp"; found=1 } 1' "${initdir}/etc/ssh/sshd_config.bak" >"${initdir}/etc/ssh/sshd_config"
  fi

}
