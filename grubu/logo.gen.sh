#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#:  __                                                :
#: |  '         |                                     :
#: | __  __     |_      __  |_ ' __   __  |_  __   __ :
#: |  | |   | | | | | | | | |  | | | /  \ |  /  \ |   :
#: '__' |   |_| |_| |_| | | |_ | | | \_/| |_ \__/ |   :
#:                                                    :


function logo_cli_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFFILE="$(readlink -m -- "$BASH_SOURCE")"
  local SELFPATH="$(dirname -- "$SELFFILE")"
  cd -- "$SELFPATH" || return $?
  sed -nre 's~:$~~; s~^#:~~p' -- "$SELFFILE" |
    # sed -re '1p;$p' | sed -re '1s~\S~ ~g; $s~\S~ ~g' |
    sed -re 's|\\|&&|g' |
    sed -re 's|^|echo \x22   |; s|$|\x22|' |
    sed -re '/\/  \\/s|"$|  @ \$hostname"|' |
    tee -- logo.grub
}










logo_cli_init "$@"; exit $?
