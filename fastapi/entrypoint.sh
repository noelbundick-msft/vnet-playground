#!/bin/sh
set -euo pipefail

rc-status
rc-service sshd start

# use the following command to load in all the environment variables from the container launch process in an ssh session
# source <(cat /proc/1/environ | strings | sed -r 's/(.*)/export \1/g')

exec "$@"
