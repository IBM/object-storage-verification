#!/usr/bin/env bash

#
# Copyright (c) 2023 IBM Corporation
# All rights reserved
#

# Treat unset variables as errors
set -u

# Exit pipes with non-zero status
set -o pipefail

# Get script name
SCRIPTNAME=$(basename "$0")

#
# Constants
#
SWIFT_DOMAIN="default"
SWIFT_PROTOCOL="http"
SWIFT_CONTAINER="swiftcurl_test"
SWIFT_POLICY="${SWIFT_POLICY:-policy-0}"
SWIFT_OBJECT="${HOSTNAME}_data_$(date +%F)"

#
# Helper functions
#
echoerr() { echo "$@" 1>&2; }

environment() {
  echoerr
  echoerr "Please define the following environment variables:"
  echoerr "  SWIFT_IP"
  echoerr "  SWIFT_USER"
  echoerr "  SWIFT_PASSWORD"
  echoerr "  SWIFT_PROJECT"
  echoerr

  exit 1
}

tmpfile() {
  mktemp "/tmp/${SCRIPTNAME}.XXXXXXXXXX"
}
trap 'rm -f /tmp/${SCRIPTNAME}.*' EXIT

runcmd() {
  [ -z ${DEBUG+x} ] || echo -e "\n$*"

  result_file=$(tmpfile)
  if ! http_code=$(eval "$* --output $result_file --write-out \"%{http_code}\"") ; then
    echoerr "ERROR!"
    echoerr "The following command failed:"
    echoerr "  $*"
    echoerr

    exit 1
  fi

  if [ "$http_code" -lt 200 ] || [ "$http_code" -gt 299 ] ; then
    echoerr "ERROR! ($http_code)"
    echoerr "The following command failed:"
    echoerr "  $*"
    [ -z ${DEBUG+x} ] || echoerr -e "\n$(cat "$result_file")"
    echoerr

    exit 1
  fi

  echo "SUCCESS! ($http_code)"
  echo

  result=$(tr -d '\0' < "$result_file")
}

#
# Sanity checks
#
[ -z ${SWIFT_IP+x} ] || \
[ -z ${SWIFT_USER+x} ] || \
[ -z ${SWIFT_PASSWORD+x} ] || \
[ -z ${SWIFT_PROJECT+x} ] && environment

if ! curl --version &> /dev/null ; then
  echoerr
  echoerr "curl not found!"
  echoerr "Refer to https://curl.se for installation instructions."
  echoerr

  exit 1
fi

#
# Obtain Authentication Token
#
echo -n "Obtaining authentication token... "

auth_json=$(tmpfile)
cat <<EOF > "$auth_json"
{ "auth": {
    "identity": {
      "methods": ["password"],
      "password": {
        "user": {
          "name": "$SWIFT_USER",
          "domain": { "id": "$SWIFT_DOMAIN" },
          "password": "$SWIFT_PASSWORD"
        }
      }
    },
    "scope": {
      "project": {
        "name": "$SWIFT_PROJECT",
        "domain": { "id": "$SWIFT_DOMAIN" }
      }
    }
  }
}
EOF

runcmd curl --silent --show-error \
  --header \"Content-Type: application/json\; charset=utf-8\" \
  --include \
  --data @"$auth_json" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:35357/v3/auth/tokens"

auth_token=$(echo "$result" | awk '/X-Subject-Token:/{print $2}' | tr -d '\r')

#
# Obtain Project ID
#
echo -n "Obtaining project ID... "

runcmd curl --silent --show-error \
  --header \"X-Auth-Token: "$auth_token"\" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:35357/v3/projects"

project_id=$(echo "$result" | python3 -mjson.tool | grep -B 1 "\"name\": \"$SWIFT_PROJECT\"" | awk '/"id":/{print $2}' | tr -d '",')

#
# Get Project Information
#
echo -n "Getting project information... "

runcmd curl --silent --show-error \
  --header \"X-Auth-Token: "$auth_token"\" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:8080/v1/AUTH_${project_id}/"

#
# Create Test Container
#
echo -n "Creating test container... "

runcmd curl --silent --show-error \
  --header \"X-Auth-Token: "$auth_token"\" \
  --header \"X-Storage-Policy: "$SWIFT_POLICY"\" \
  --request PUT \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:8080/v1/AUTH_${project_id}/${SWIFT_CONTAINER}"

#
# Upload Test Object
#
echo -n "Uploading test object... "

temp_data=$(tmpfile)
dd if=/dev/urandom of="$temp_data" bs=1M count=10 &> /dev/null

runcmd curl --silent --show-error \
  --header \"X-Auth-Token: "$auth_token"\" \
  --request PUT \
  --data-binary @"$temp_data" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:8080/v1/AUTH_${project_id}/${SWIFT_CONTAINER}/${SWIFT_OBJECT}"

#
# Get Information About Container
#
echo -n "Getting information about container... "

runcmd curl --silent --show-error \
  --header \"X-Auth-Token: "$auth_token"\" \
  --head \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:8080/v1/AUTH_${project_id}/${SWIFT_CONTAINER}"

#
# Get Information About Object
#
echo -n "Getting information about object... "

runcmd curl --silent --show-error \
  --header \"X-Auth-Token: "$auth_token"\" \
  --head \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:8080/v1/AUTH_${project_id}/${SWIFT_CONTAINER}/${SWIFT_OBJECT}"

#
# Download Test Object
#
echo -n "Downloading test object... "

runcmd curl --silent --show-error \
  --header \"X-Auth-Token: "$auth_token"\" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:8080/v1/AUTH_${project_id}/${SWIFT_CONTAINER}/${SWIFT_OBJECT}"

#
# Revoke Authentication Token
#
echo -n "Revoking authentication token... "

runcmd curl --silent --show-error \
  --header \"X-Auth-Token: "$auth_token"\" \
  --header \"X-Subject-Token: "$auth_token"\" \
  --request DELETE \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:35357/v3/auth/tokens"

echo "All tests successful! 🎉 Exiting..."

exit 0