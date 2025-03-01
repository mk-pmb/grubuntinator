#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function qemu_boot () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH" || return $?

  local BOOTDISK="$QEMU_BOOTDISK"
  local OVL_FILE="$QEMU_OVERLAY_FILE"
  local BIOS="$QEMU_FIRMWARE"

  local QTMP="$QEMU_TMPDIR"
  [ -n "$QTMP" ] || QTMP="$XDG_RUNTIME_DIR"
  [ -d "$QTMP" ] || QTMP="$TMPDIR"
  [ -d "$QTMP" ] || QTMP='/tmp'
  QTMP+='/qemu'
  mkdir --parents --mode=0700 -- "$QTMP" || return $?

  local QEMU_FLAGS=",$QEMU_FLAGS,"

  local VAL=
  while [ "${1:0:1}" == - ]; do
    VAL="$1"; shift
    case "$VAL" in
      -- ) break;;
      --sudo | \
      -- ) QEMU_FLAGS+="${VAL#--},";;
      --ro-usb ) BOOTDISK='usb:'; OVL_FILE='ram:';;
      * ) echo E: "Unsupported CLI option: $1" >&2; return 4;;
    esac
  done
  [ "$#" == 0 ] || return 4$(echo E: "Unsupported CLI argument: $1" >&2)

  case "$BOOTDISK" in
    '' ) BOOTDISK='tmp.disk.img';;
    usb: )
      BOOTDISK="$(printf -- '%s\n' /dev/disk/by-id/usb-* | grep -vFe '-part' |
        sort --version-sort | head --lines=1)"
      [ -b "$BOOTDISK" -a ! -r "$BOOTDISK" ] && QEMU_FLAGS+='sudo,'
      ;;
  esac
  [ -f "$BOOTDISK" ] || [ -b "$BOOTDISK" ] || return 4$(echo E: >&2 \
    "Boot disk must be a file or a block device: ${BOOTDISK:-(none)}")

  [ -n "$QEMU_SERIAL_TCP_PORT" ] || local QEMU_SERIAL_TCP_PORT=$(
    )30865 # csync2 should be rare on a dev machine.
  [ -n "$QEMU_RAM_LIMIT_MB" ] || local QEMU_RAM_LIMIT_MB=128

  case "$BIOS" in
    efi | '' ) BIOS='/usr/share/ovmf/OVMF.fd';;
  esac

  local OVL_FMT="${QEMU_OVERLAY_FORMAT:-qcow2}"
  local OVL_SIZE_MB="$QEMU_OVERLAY_SIZE_MB"
  if [ "$OVL_FILE" == ram: ]; then
    OVL_FILE="$QTMP/readonly-disk-overlays"
    mkdir --parents --mode=0700 -- "$OVL_FILE" || return $?
    OVL_FILE="$(mktemp --tmpdir="$OVL_FILE" --suffix=".$OVL_FMT")"
    [ -f "$OVL_FILE" ] || return 4$(
      echo E: 'Failed to create temporaty overlay file: $OVL_FILE' >&2)
    qemu-img create -f "$OVL_FMT" \
      -- "$OVL_FILE" "${OVL_SIZE_MB:-1}"M || return $?$(
      echo E: 'Failed to format temporaty overlay file: $OVL_FILE' >&2)
    ( sleep 10s && rm -- "$OVL_FILE" ) & disown $!
  fi

  local BOOT_CMD=()
  [[ "$QEMU_FLAGS" == *,sudo,* ]] && BOOT_CMD+=( sudo -E )
  BOOT_CMD+=(
    qemu-system-"$(uname -m)"
    -machine pc
    -m "$QEMU_RAM_LIMIT_MB"M
    -bios "$BIOS"
    # -monitor stdio
    -display gtk
    -usb
    -only-migratable
    -drive if=virtio,file="$BOOTDISK",format=raw,media=disk$(
      [ -z "$OVL_FILE" ] || echo ,readonly=on)
    )
  [ -z "$OVL_FILE" ] || BOOT_CMD+=(
    -drive id=drv0,if=none,file="$OVL_FILE",driver="$OVL_FMT"
    -device virtio-blk-pci,drive=drv0
    )

  for VAL in $QEMU_CDROMS ; do
    [ -f "$VAL" ] || continue
    BOOT_CMD+=( -drive file="$VAL",media=cdrom )
  done
  for VAL in $QEMU_HARDDISKS ; do
    [ -f "$VAL" ] || continue
    BOOT_CMD+=( -drive file="$VAL",format=raw,media=disk )
  done

  # Boot only the bootdisk, don't try optical media or network:
  BOOT_CMD+=( -boot menu=off,strict=on,order=c )

  # Try to disable mouse grabbing:
  BOOT_CMD+=(
    -show-cursor # useless
    -device usb-tablet # useless
    # -display gtk,show-cursor=on # Parameter 'show-cursor' is unexpected
    )

  [ -z "$QEMU_GUEST_NAME" ] || BOOT_CMD+=( -name "$GUEST_NAME" )
  [ -z "$QEMU_GUEST_UUID" ] || BOOT_CMD+=( -uuid "$GUEST_UUID" )
  [ "$QEMU_SERIAL_TCP_PORT" == 0 ] || BOOT_CMD+=(
    -serial tcp:localhost:"$QEMU_SERIAL_TCP_PORT",reconnect=5 )

  echo D: "run: ${BOOT_CMD[*]}"
  "${BOOT_CMD[@]}" &
  local QEMU_PID="$!"
  disown "$QEMU_PID"
  echo D: "QEMU PID is $QEMU_PID. Waiting for its window to show up:"

  local QEMU_WIN_ID=
  SECONDS=0
  while [ -z "$QEMU_WIN_ID" -a "$SECONDS" -le 10 ] && sleep 0.25s; do
    QEMU_WIN_ID="$(xdotool search --onlyvisible --pid "$QEMU_PID" --class qemu)"
  done
  [ -n "$QEMU_WIN_ID" ] || return 4$(
    echo E: 'Timeout waiting for QEMU window to appear.' >&2)
  printf -v QEMU_WIN_ID '0x%08x' "$QEMU_WIN_ID"
  echo D: "Found QEMU_WIN_ID=$QEMU_WIN_ID"

  local DESKTOP_WIDTH=0 DESKTOP_HEIGHT=0
  eval "$(wmctrl -d | sed -nre 's~^\S+\s+\* DG: ([0-9]+)x([0-9]+) .*$'$(
    )'~DESKTOP_WIDTH=\1 DESKTOP_HEIGHT=\2~p')"
  wmctrl -iFr "$QEMU_WIN_ID" -b add,above
  VAL="${QEMU_WINPOS_X:--840}"
  [ "$VAL" -ge 0 ] || (( VAL += DESKTOP_WIDTH ))
  [ "$VAL" -ge 1 ] || VAL=0
  wmctrl -iFr "$QEMU_WIN_ID" -e 0,"$VAL",0,-1,-1

  wmctrl -iFr "$QEMU_WIN_ID" -N "QEMU pid=$QEMU_PID"$(
    )' H: The default power-off shortcut is ctrl+alt+q.'
  # NB: QEMU will automatically show a window title hint about ctrl+alt+q
  #     when mouse grabbing activates.
}











qemu_boot "$@"; exit $?
