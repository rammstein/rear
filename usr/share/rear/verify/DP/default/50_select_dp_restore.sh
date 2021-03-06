##############################################################################
#
# Select dataprotector backup to be restored
#
# Ends in:
#   /tmp/dp_recovery_host     - the host to be restored
#   /tmp/dp_recovery_devs     - the devices used during backup
#   /tmp/dp_recovery_session  - the session to be restored
#   /tmp/dp_recovery_datalist - the datalist to be restored
#

#set -e

[ -f /tmp/DP_GUI_RESTORE ] && return # GUI restore explicetely requested


OMNIDB=/opt/omni/bin/omnidb
OMNICELLINFO=/opt/omni/bin/omnicellinfo

HOST="`hostname`"

DPGetBackupList() {
  if test $# -gt 0 ; then
    HOST=$1
  else
    HOST="`hostname`"
  fi >&2
  test -f /tmp/dp_list_of_sessions.in && rm -f /tmp/dp_list_of_sessions.in
  touch /tmp/dp_list_of_sessions.in
  ${OMNIDB} -filesystem | grep "${HOST}" | cut -d"'" -f -2 > /tmp/dp_list_of_fs_objects
  cat /tmp/dp_list_of_fs_objects | while read object; do
    host_fs=`echo ${object} | awk '{print $1}'`
    fs=`echo ${object} | awk '{print $1}' | cut -d: -f 2`
    label=`echo "${object}" | cut -d"'" -f 2`
    ${OMNIDB} -filesystem $host_fs "$label" | grep -v "^SessionID" | grep -v "^===========" | awk '{ print $1 }' >> /tmp/dp_list_of_sessions.in
  done
  sort -u -r < /tmp/dp_list_of_sessions.in > /tmp/dp_list_of_sessions
  cat /tmp/dp_list_of_sessions | while read sessid; do
    datalist=$(${OMNIDB} -session $sessid -report | grep BSM | cut -d\" -f 2 | head -1)
    device=$(${OMNIDB} -session $sessid -detail | grep "Device name" | cut -d: -f 2 | awk '{ print $1 }' | sort -u)
    media=$(${OMNIDB} -session $sessid -media | grep -v "^Medium Label" | grep -v "^=====" | awk '{ print $1 }' | sort -u)
    if test -n "$datalist"; then
      echo -e "$sessid\t$datalist\t$(echo $device)\t$(echo $media)\t$HOST"
    fi
  done
}

DPChooseBackup() {
  if test $# -gt 0 ; then
    HOST=$1
  else
    HOST="`hostname`"
  fi >&2
  LogPrint "Scanning for DP backups for Host ${HOST}"
  DPGetBackupList $HOST > /tmp/backup.list
  >/tmp/backup.list.part

  SESSION=$(head -1 /tmp/backup.list | cut -f 1)
  DATALIST=$(head -1 /tmp/backup.list | cut -f 2)
  DEVS=$(head -1 /tmp/backup.list | cut -f 3)
  MEDIA=$(head -1 /tmp/backup.list | cut -f 4)
  HOST=$(head -1 /tmp/backup.list | cut -f 5)

  while true; do
    LogPrint ""
    LogPrint "Found DP-Backup:"
    LogPrint ""
    LogPrint "  [H] Host........: $HOST"
    LogPrint "  [D] Datalist....: $DATALIST"
    LogPrint "  [S] Session.....: $SESSION"
    LogPrint "      Device(s)...: $DEVS"
    LogPrint "      Media(s)....: $MEDIA"
    LogPrint ""
    unset REPLY
    read -t 30 -r -n 1 -p "press ENTER or choose H,D,S [30sec]: " 2>&1

    if test -z "${REPLY}"; then
      echo $HOST > /tmp/dp_recovery_host
      echo $SESSION > /tmp/dp_recovery_session
      echo $DATALIST > /tmp/dp_recovery_datalist
      echo $DEVS > /tmp/dp_recovery_devs
      LogPrint "ok"
      return
    elif test "${REPLY}" = "h" -o "${REPLY}" = "H"; then
      DPChangeHost
      return
    elif test "${REPLY}" = "d" -o "${REPLY}" = "D"; then
      local DL=test
      DPChangeDataList
      >/tmp/backup.list.part
      cat /tmp/backup.list | while read s; do
        DATALIST=$(echo "$s" | cut -f 2)
        if test $DATALIST = $DL; then echo "$s" >> /tmp/backup.list.part; fi
      done
      SESSION=$(head -1 /tmp/backup.list.part | cut -f 1)
      DATALIST=$(head -1 /tmp/backup.list.part | cut -f 2)
      DEVS=$(head -1 /tmp/backup.list.part | cut -f 3)
      MEDIA=$(head -1 /tmp/backup.list.part | cut -f 4)
      HOST=$(head -1 /tmp/backup.list.part | cut -f 5)
    elif test "${REPLY}" = "s" -o "${REPLY}" = "S"; then
      local SESS=$SESSION
      DPChangeSession
      SESSION=$SESS
      DATALIST=$(grep "^$SESS" /tmp/backup.list | cut -f 2)
      DEVS=$(grep "^$SESS" /tmp/backup.list| cut -f 3)
      MEDIA=$(grep "^$SESS" /tmp/backup.list | cut -f 4)
      HOST=$(grep "^$SESS" /tmp/backup.list | cut -f 5)
    fi
  done
}

DPChangeHost() {
  valid=0
  while test $valid -eq 0; do
    echo ""
    read -r -p "Enter host: " 2>&1
    if test -z "${REPLY}"; then
      DPChooseBackup
      return
    fi
    if ${OMNICELLINFO} -cell | grep -q "host=\"${REPLY}\""; then
      valid=1
    else
      LogPrint "Invalid hostname '${REPLY}'!"
    fi
  done
  DPChooseBackup ${REPLY}
}

DPChangeDataList() {
  valid=0
  while test $valid -eq 0; do
    LogPrint ""
    LogPrint ""
    LogPrint "Available datalists for host:"
    LogPrint ""
    i=0
    cat /tmp/backup.list | while read s; do echo "$s" | cut -f 2; done | sort -u | while read s; do
      i=$(expr $i + 1)
      LogPrint "  [$i] $s"
    done
    i=$(cat /tmp/backup.list | while read s; do echo "$s" | cut -f 2; done | sort -u | wc -l)
    LogPrint ""
    read -r -p "Please choose datalist [1-$i]: " 2>&1
    if test "${REPLY}" -ge 1 -a "${REPLY}" -le $i 2>&8; then
      DL=$(cat /tmp/backup.list | while read s; do echo "$s" | cut -f 2; done | sort -u | head -${REPLY} | tail -1)
      valid=1
    else
      LogPrint "Invalid number '${REPLY}'!"
    fi
  done
}

DPChangeSession() {
  valid=0
  while test $valid -eq 0; do
    LogPrint ""
    LogPrint ""
    LogPrint "Available sessions for datalist:"
    LogPrint ""
    i=0
    if test ! -s /tmp/backup.list.part; then cp /tmp/backup.list /tmp/backup.list.part; fi
    cat /tmp/backup.list.part | while read s; do echo "$s" | cut -f 1; done | sort -u -r | while read s; do
      i=$(expr $i + 1)
      LogPrint "  [$i] $s"
    done
    i=$(cat /tmp/backup.list.part | while read s; do echo "$s" | cut -f 1; done | sort -u -r | wc -l)
    echo
    read -r -p "Please choose session [1-$i]: " 2>&1
    if test "${REPLY}" -ge 1 -a "${REPLY}" -le $i 2>&8; then
      SESS=$(cat /tmp/backup.list.part | while read s; do echo "$s" | cut -f 1; done | sort -u -r | head -${REPLY} | tail -1)
      valid=1
    else
      LogPrint "Invalid number '${REPLY}!"
    fi
  done
}

DPChooseBackup
