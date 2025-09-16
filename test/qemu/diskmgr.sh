#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function diskmgr_cli_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH" || return $?

  local ADM_GROUP_GID="$(grep -e '^adm:' -- /etc/group | cut -d : -f 3)"
  local -A DISKIMG=(
    [file]='tmp.disk.img'
    [size_mb]=2048
    # ^-- Meant to give enough storage in the ISO bay to carry the live ISO
    #     from ubborg-usecase-rescuedisk-pmb.

    [prtn_shortnames]='esp bay'
    [disk_guid]='6727b3ce-35b7-45af-803d-07d37befd490'

    [esp:guid]='e9f40dc2-67a5-4c4b-bf12-5c8caf171ce5'
    [esp:type]='EF00' # EFI system partition
    [esp:pt_label]='qemutest_esp'
    [esp:fat_volume_id]="$(diskmgr_hexencode 'GRUB')"
    [esp:fat_volume_name]='qemu_grub'
    [esp:size]='16M'
    [esp:mount_opt]=",dmask=0022,fmask=0133,$(stat --format=uid=%u,gid=%g .)"

    [bay:guid]='dfa75d2b-c47e-4f4c-8a65-e03fed26735b'
    # [bay:type]='0700' # Microsoft basic data'
    [bay:type]='8300' # Linux filesystem
    [bay:pt_label]='qemutest_isobay'
    # [bay:fat_volume_id]="$(diskmgr_hexencode 'ISOS')"
    # [bay:fat_volume_name]='QEMU_ISOBAY'
    [bay:fs_uuid]='f3102cb0-8a4b-4d7c-8649-af267709609d'
    [bay:fs_label]='' # empty = use pt_label
    [bay:size]='' # empty = use all remaining space

    )

  DISKIMG[grubenv:hostname]="${DISKIMG[bay:pt_label]%%_*}"
  DISKIMG[grubenv:liveiso_prtn]="${DISKIMG[bay:pt_label]}"

  diskmgr_detect_loopdev || return $?

  diskmgr_"$@" || return $?
}


function diskmgr_hexencode () { echo -n "$1" | od -A n -t x1 | tr -d ' '; }


function diskmgr_status () {
  declare -p | sed -nre 's~ \[~\n\t[~g; s~^declare -\S (DISKIMG)=~\1=~p'
}


function diskmgr_detect_loopdev () {
  local LOOP="$(losetup --associated "${DISKIMG[file]}")"
  #                                 ^-- no '--' here!!
  LOOP="${LOOP%%:*}"
  DISKIMG[loop_dev]="$LOOP"
}


function diskmgr_mount () {
  diskmgr_mount__disk_only || return $?
  diskmgr_mount__mpnt_only || return $?
}


function diskmgr_mount__disk_only () {
  sudo losetup --nooverlap --find -- "${DISKIMG[file]}" || return $?
  diskmgr_detect_loopdev || return $?
  sudo losetup --set-capacity "${DISKIMG[loop_dev]}" || return $?
  sudo partprobe -- "${DISKIMG[loop_dev]}" || return $?
  diskmgr_status || return $?
}


function diskmgr_mount__mpnt_only () {
  local SHORTNAME= DISK= NUM=0 MPNT= MOPT= HAVE=
  for SHORTNAME in ${DISKIMG[prtn_shortnames]} ; do
    mkdir --parents -- tmp."$SHORTNAME" || return $?
    (( NUM += 1 ))
    DISK="${DISKIMG[loop_dev]}p$NUM"
    MPNT="tmp.$SHORTNAME"
    MOPT="defaults,noatime${DISKIMG[$SHORTNAME:mount_opt]}"
    HAVE="$(readlink -m -- "$MPNT")"
    [ "$HAVE" -ef "$MPNT" ] || return 4$(
      echo E: "Failed to resolve symlink: $MPNT" >&2)
    HAVE="$(mount | LANG=C grep -Fe " on $HAVE type ")"
    [ "${HAVE%% on *}" == "$DISK" ] ||
      sudo mount "$DISK" "$MPNT" -o "$MOPT" || return $?
  done
}


function diskmgr_eject () {
  diskmgr_umount__mpnt_only || return $?
  sudo losetup --detach "${DISKIMG[loop_dev]}" || return $?$(
    echo E: $FUNCNAME: "Failed to detach '${DISKIMG[loop_dev]}': rv=$?" >&2)
}


function diskmgr_umount__mpnt_only () {
  local VAL=
  for VAL in ${DISKIMG[prtn_shortnames]} ; do
    VAL="tmp.$VAL"
    mountpoint --quiet -- "$VAL" || continue
    sudo umount -- "$VAL" || return $?
  done
}


function diskmgr_read_prtntbl () {
  eval -- "$(./sgdisk-parse-sectors.sh "${DISKIMG[file]}" DISKIMG)"
}


function diskmgr_remake () {
  diskmgr_umount__mpnt_only || return $?
  truncate --size="${DISKIMG[size_mb]}"M -- "${DISKIMG[file]}" || return $?

  echo D: 'zap potential old partition table(s):'
  sgdisk --zap-all -- "${DISKIMG[file]}" || return $?
  echo

  echo D: 'write partition table:'
  local SGD_JOB=(
    --clear
    --disk-guid="${DISKIMG[disk_guid]}"
    )
  local PRTN=
  for PRTN in ${DISKIMG[prtn_shortnames]} ; do
    SGD_JOB+=(
      --new=0::"${DISKIMG[$PRTN:size]}"
      --typecode=0:"${DISKIMG[$PRTN:type]}"
      --change-name=0:"${DISKIMG[$PRTN:pt_label]}"
      --partition-guid=0:"${DISKIMG[$PRTN:guid]}"
      )
  done
  sgdisk "${SGD_JOB[@]}" -- "${DISKIMG[file]}" || return $?
  echo

  diskmgr_mount__disk_only || return $?
  diskmgr_detect_loopdev || return $?

  diskmgr_neuter_partition 0 || return $?
  sudo mkfs.fat \
    -i "${DISKIMG[esp:fat_volume_id]}" \
    -n "${DISKIMG[esp:fat_volume_name]}" \
    -- "${DISKIMG[loop_dev]}p1"  || return $?

  local EXT_OPT=(
    -j    # create an ext3 journal
    -m 0  # reserved blocks percentage
    )
  diskmgr_neuter_partition 1 || return $?
  sudo mkfs.ext3 "${EXT_OPT[@]}" -U "${DISKIMG[bay:fs_uuid]}" \
    -L "${DISKIMG[bay:fs_label]:-${DISKIMG[bay:pt_label]}}" \
    -- "${DISKIMG[loop_dev]}p2"  || return $?

  diskmgr_install_grub || return $?
  diskmgr_configure_grub || return $?
  diskmgr_postmake || return $?
}


function diskmgr_neuter_partition () {
  sudo dd if=/dev/zero of="${DISKIMG[loop_dev]}p${1:-E_NO_PRTN_NUM}" \
    bs=1024 count=1024 || return $?
}


function diskmgr_install_grub () {
  diskmgr_mount__mpnt_only || return $?

  sudo grub-install --skip-fs-probe --removable --no-nvram \
    --target="$(uname -m)"-efi --{boot,efi}-directory=tmp.esp/ \
    -- "${DISKIMG[loop_dev]}p1" || return $?
  echo
}


function diskmgr_configure_grub () {
  [ -n "$GRUB_CFGDIR" ] || local GRUB_CFGDIR='../..'
  GRUB_CFGDIR="${GRUB_CFGDIR%/}"
  echo D: "Gonna copy GRUB config files from: $GRUB_CFGDIR/"
  local ORIG= SXS=0
  for ORIG in "$GRUB_CFGDIR"/{grub.*,*.grub} ; do
    [ -f "$ORIG" ] || continue
    case "ORIG" in
      *.@* ) continue;;
    esac
    cp --target-directory=tmp.esp/grub/ -- "$ORIG" || return $?$(
      echo E: "Failed to copy GRUB config file '$ORIG'!" >&2)
    (( SXS += 1 ))
  done
  echo D: "Copied $SXS GRUB config files."

  echo D: 'Writing grubenv file:'
  diskmgr_gen_grubenv >tmp.esp/grub/grubenv || return $?

  echo D: 'Done configuring GRUB.'
}


function diskmgr_gen_grubenv () {
  local KEY= VAL= GE_LEN=1024
  ( echo '# GRUB Environment Block'
    for KEY in "${!DISKIMG[@]}"; do
      case "$KEY" in
        grubenv:* )
          VAL="${DISKIMG[$KEY]}"
          echo "${KEY#*:}=$VAL"
          ;;
      esac
    done | sort -V
    yes | head --bytes="$GE_LEN" | tr -c '#' '#'
  ) | head --bytes="$GE_LEN"
}


function diskmgr_postmake () {
  diskmgr_mount__mpnt_only || return $?
  sudo mkdir --parents -- tmp.bay/boot-isos || return $?
  sudo chown --reference . --recursive -- tmp.bay/boot-isos || return $?
}











diskmgr_cli_init "$@"; exit $?
