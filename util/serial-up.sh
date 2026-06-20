#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
[ -n "$*" ] || exit 4$(
  echo E: "No filenames given! Use '.' for default files." >&2)
if [ "$1" == . ]; then
  shift
  set -- $(ls -1 -- *.grub | grep -vFe .@) "$@"
fi
UPLOADER='serialport-upload-to-busybox-initrd' # from net-util-pmb
exec $UPLOADER --into //ESP//grub/ "$@"; exit $?
