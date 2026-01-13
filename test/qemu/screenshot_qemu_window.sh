#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function sshot_qemu_win () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH" || return $?
  local SAVE_AS="tmp.sshot/$(printf '%(%y%m%d-%H%M%S)T' -1)."
  mkdir --parents -- "${SAVE_AS%/*}"
  local WIN_ID="$(wmctrl -xl |
    grep -oPe '^0x\S+\s+\S+\s+qemu\.Qemu-system-' | grep -oPe '^0x\S+')"
  [ -n "$WIN_ID" ] || return 4$(echo E: 'Failed to detect QEMU window id!' >&2)
  SAVE_AS+="qemu.$WIN_ID.png"
  echo D: "Gonna screenshot window $WIN_ID as: $SAVE_AS"
  convert x:"$WIN_ID" "$SAVE_AS" || return $?
}



sshot_qemu_win "$@"; exit $?
