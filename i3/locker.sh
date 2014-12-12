#!/bin/sh

exec xautolock -detectsleep 
  -time 5 -locker "i3lock-wrapper -d" \
  -notify 30 \
  -notifier "notify-send -u critical -t 10000 -- 'LOCKING screen in 30 seconds'"

exec xautolock -time 10 -locker "systemctl suspend" -detectsleep
