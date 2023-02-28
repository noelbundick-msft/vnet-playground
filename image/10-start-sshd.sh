#!/bin/sh
set -euo pipefail

rc-status
rc-service sshd start

# HACK: add env vars to /etc/profile
# https://learn.microsoft.com/en-us/answers/questions/179503/webapp-for-containers-app-settings-not-passed-thro
eval $(printenv | sed -n "s/^\([^=]\+\)=\(.*\)$/export \1=\2/p" | sed 's/"/\\\"/g' | sed '/=/s//="/' | sed 's/$/"/' >> /etc/profile)  
