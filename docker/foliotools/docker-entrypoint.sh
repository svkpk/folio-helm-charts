#!/bin/bash

cd `dirname $0`

main() {
  local INITSCRIPT=$1
  echo "-- Waiting for file $INITSCRIPT..."
  local TRY_COUNT=20
  while [ true ]; do
    if [ $TRY_COUNT = 0 ]; then break; fi
      echo -ne "testing if $INITSCRIPT exists..."
      if [ -f "$INITSCRIPT" ]; then
        echo "done"
        exec $INITSCRIPT
        return 0
      fi 
    let TRY_COUNT=$TRY_COUNT-1
    echo "not ready, trying $TRY_COUNT more times..."
    sleep 1
  done
  return 1
}

main $1
