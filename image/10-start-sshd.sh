#!/bin/sh
set -euo pipefail

rc-status
rc-service sshd start
