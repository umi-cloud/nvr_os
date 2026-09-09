#!/bin/sh
sudo mkdir -p /mnt/nfsdir
if [ ! -n "${1}" ]; then
        IP_SERVER="192.168.0.10"
else
        IP_SERVER="${1}"
fi
echo "IP_SERVER=${IP_SERVER}"
sudo busybox mount -t nfs -o rw,nolock ${IP_SERVER}:/srv/nfs4 /mnt/nfsdir
# sudo busybox mount -t nfs -o rw,nolock 192.168.0.10:/srv/nfs4 /mnt/nfsdir
