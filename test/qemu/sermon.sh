#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#
# SerMon = serial (port) monitor

function sermon_cli_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFFILE="$(readlink -m -- "$BASH_SOURCE")"
  local SELFPATH="$(dirname -- "$SELFFILE")"
  # cd -- "$SELFPATH" || return $?

  local PORT="${1:-30865}"
  local TASK="${1:-listen}"
  sermon_"$TASK" "$@"; return $?
}


function sermon_listen () {
  clear
  local IN_LINK='tmp.sermon.in'
  local LSN_PROG='netcat'
  exec 4<> >(:)
  exec 5< <(exec -a qemu-sermon "$LSN_PROG" -vvvlp "$PORT" <&4 2>&1)
  local NC_PID=$!
  echo D: "sermon pid: $$ | $LSN_PROG pid: $NC_PID |" \
    'Wait for $LSN_PROG startup message(s):'
  local BUF= RV=
  # If we instantly have input available, it's probably just necat init
  # messages, not worth starting the log file yet.
  BUF=10
  while IFS= read -rsu 5 -t $BUF BUF; do echo "$BUF"; BUF=2; done

  echo "D: $LSN_PROG seems ready, wait for connection:"
  # First byte after a moment of silence means we have an actual connection:
  IFS= read -rsu 5 -N 1 BUF; RV=$?
  [ "$RV" == 0 ] || return $RV$(echo E: $FUNCNAME: >&2 \
    "Failed (rv=$RV) to read first character!")

  local LOGF="tmp.sermon.$(printf -- '%(%d%m%y-%H%M%S)T' -1).$$.$PORT.log"
  echo -n "$BUF" >"$LOGF" || return $RV$(echo E: $FUNCNAME: >&2 \
    "Failed (rv=$RV) to write first character to log!")
  local LNST='ln --symbolic --force --verbose --no-target-directory'
  $LNST -- "/proc/$NC_PID/fd/0" "$IN_LINK"
  $LNST -- "$LOGF" tmp.sermon.log
  echo -n "$BUF"
  unbuffered tee --append -- "$LOGF" <&5 | sermon_track_grub_cursor

  exec 4<&- 5<&-
  rm -- "$IN_LINK"
  "$SELFFILE" cleanlog <"$LOGF" | sponge "$LOGF"
  gtame default-x-text-editor "$LOGF"
  wait
}


function sermon_track_grub_cursor () {
  local ANIM_SYMB=( '|' '¦' )
  ANIM_SYMB=( '╎' '╏' )
  ANIM_SYMB=( █ ' ' )
  ANIM_SYMB=( '▋' '▒' )
  ANIM_SYMB=( '·' '•' )

  local ANIM_STEP=0 ANIM_N_SYMB="${#ANIM_SYMB[@]}"
  local BUF= RV=
  while true; do
    IFS= read -n 1 -rst 0.4 BUF
    RV=$?
    if [ "$RV" -ge 128 ]; then
      # Timeout
      (( ANIM_STEP %= ANIM_N_SYMB ))
      echo -ne ' \b'
      echo -n "${ANIM_SYMB[$ANIM_STEP]}"
      echo -ne '\b'
      (( ANIM_STEP += 1 ))
      continue
    fi
    [ "$RV" == 0 ] || return $RV
    IDLE_CTR=0
    [ -n "$BUF" ] && echo -n "$BUF" || echo
  done
}


function csed () { LANG=C sed "$@"; }


function sermon_cleanlog () {
  tty --silent && echo D: $FUNCNAME: 'reading from stdin.' >&2 || true
  csed -urf <(echo '
    s~(.)(\x1B\[[0-9;]+H)~\1\n\2~g

    /^=+ clear screen =+$/N
    s~(^|[^\n])(\x1B\[2J)|$\
      ~\1\n\n\n==================== clear screen ====================\n\2\n~g
    ') |
    csed -ure 's!^\r!!g; s!\r$!!g; s!\r!«!g' |
    csed -ure 's!^((\x1B\[[0-9;]+[A-Za-z])+)([^\x1B])!\1\n\3!' |
    csed -urf <(echo '
    s!\x1B!^E!g


    $s~.$~&\n~
    ')
}










sermon_cli_init "$@"; exit $?
