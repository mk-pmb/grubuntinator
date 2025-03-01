#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
LANG=C sgdisk --print -- "$1" | sed -re 's~, ~\n~' | sed -nrf <(echo '
    s~[A-Z]+~\L&\E~g
    s~^(sector size) \(logical\): ([0-9]+) bytes$~[\1]=\2~p
    s~^((first|last) usable sector) is ([0-9]+)$~[\1]=\3~p
    s~^partitions will be (align)ed on ([0-9]+)-sector boundaries$|\
      ~[\1ment]=\2~p
  ') | tr -s ' \t' _ | sed -re "s~^~$2~"
