#!/usr/bin/sh
export PATH=$PATH:/local/conda/envs/python-nest/bin

type info >/dev/null 2>&1 || . /lib/dracut-lib.sh
info "Waiting for Ansible to create me a roofs..."
X=$(awk '{print int($1)}' /proc/uptime)
MSG=""
while [ ! -f "/tmp/ansible-finished" ]; do
  let X+=5
  sleep 5
  [ -f /tmp/message ]&&MSG=$(cat /tmp/message)
  echo "$(date -u -d @${X} +'%T'): Waiting for Ansible; $MSG" >>/dev/console
done
