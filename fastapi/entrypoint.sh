#!/bin/sh
set -euo pipefail

rc-status
rc-service sshd start

# use the following command to load in all the environment variables from the container launch process in an ssh session
# source <(cat /proc/1/environ | strings | sed -r 's/(.*)/export \1/g')

# use the following command to connect to postgres via AAD
#PGUSER=$APPSETTING_WEBSITE_SITE_NAME
#PGPASSWORD=$(curl -s "$IDENTITY_ENDPOINT?api-version=2019-08-01&resource=https://ossrdbms-aad.database.windows.net" -H "X-IDENTITY-HEADER: $IDENTITY_HEADER" | jq -r .access_token)


exec "$@"
