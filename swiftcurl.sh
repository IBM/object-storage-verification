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
# Default variables
#
SWIFT_DOMAIN="default"
SWIFT_PROTOCOL="${SWIFT_PROTOCOL:-http}"
if [ "$SWIFT_PROTOCOL" == "http" ] ; then
  SWIFT_AUTH_PORT="${SWIFT_AUTH_PORT:-5000}"
  SWIFT_STORAGE_PORT="${SWIFT_STORAGE_PORT:-8080}"
elif [ "$SWIFT_PROTOCOL" == "https" ] ; then
  SWIFT_AUTH_PORT="${SWIFT_AUTH_PORT:-5001}"
  SWIFT_STORAGE_PORT="${SWIFT_STORAGE_PORT:-8081}"
fi
SWIFT_CONTAINER="${SWIFT_CONTAINER:-swiftcurl_test}"
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

separator() {
  local columns
  columns=$(stty -a | grep -Po '(?<=columns )\d+')
  printf "*%.0s" $(seq 1 "${columns:-80}")
}

tmpfile() {
  mktemp "/tmp/${SCRIPTNAME}.XXXXXXXXXX"
}
trap 'rm -f /tmp/${SCRIPTNAME}.*' EXIT

runcurl() {
  [ -z ${DEBUG+x} ] || echo -e "\ncurl $*"

  local result_file http_code
  result_file=$(tmpfile)
  if ! http_code=$(eval "curl \
    --silent \
    --show-error \
    --insecure \
    --output $result_file \
    --write-out \"%{http_code}\" \
    $*")
  then
    echoerr "ERROR!"
    echoerr "The following command failed:"
    echoerr "  curl $*"
    echoerr

    exit 1
  fi

  if [ "$http_code" -lt 200 ] || [ "$http_code" -gt 299 ] ; then
    echoerr "ERROR! ($http_code)"
    echoerr "The following command failed:"
    echoerr "  curl $*"
    [ -z ${DEBUG+x} ] || echoerr -e "\n$(cat "$result_file")"
    echoerr

    exit 1
  fi

  echo "SUCCESS! ($http_code)"
  echo

  RESULT=$(tr -d '\0' < "$result_file")
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
# Print Connection Details
#
separator
echo "SWIFT_IP:           $SWIFT_IP"
echo "SWIFT_PROTOCOL:     $SWIFT_PROTOCOL"
echo "SWIFT_AUTH_PORT:    $SWIFT_AUTH_PORT"
echo "SWIFT_STORAGE_PORT: $SWIFT_STORAGE_PORT"
echo "SWIFT_USER:         $SWIFT_USER"
echo "SWIFT_PROJECT:      $SWIFT_PROJECT"
echo "SWIFT_CONTAINER:    $SWIFT_CONTAINER"
echo "SWIFT_POLICY:       $SWIFT_POLICY"
echo

#
# Obtain Authentication Token
#
separator
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

runcurl \
  --header \"Content-Type: application/json\; charset=utf-8\" \
  --include \
  --data @"$auth_json" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:${SWIFT_AUTH_PORT}/v3/auth/tokens"

auth_token=$(echo "$RESULT" | awk '/X-Subject-Token:/{print $2}' | tr -d '\r')

#
# Obtain Project ID
#
separator
echo -n "Obtaining project ID... "

runcurl \
  --header \"X-Auth-Token: "$auth_token"\" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:${SWIFT_AUTH_PORT}/v3/projects"

project_id=$(echo "$RESULT" | python3 -mjson.tool | grep -B 1 "\"name\": \"$SWIFT_PROJECT\"" | awk '/"id":/{print $2}' | tr -d '",')

#
# Get Project Information
#
separator
echo -n "Getting project information... "

runcurl \
  --header \"X-Auth-Token: "$auth_token"\" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:${SWIFT_STORAGE_PORT}/v1/AUTH_${project_id}/"

#
# Create Test Container
#
separator
echo -n "Creating test container... "

runcurl \
  --header \"X-Auth-Token: "$auth_token"\" \
  --header \"X-Storage-Policy: "$SWIFT_POLICY"\" \
  --request PUT \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:${SWIFT_STORAGE_PORT}/v1/AUTH_${project_id}/${SWIFT_CONTAINER}"

#
# Upload Test Object
#
separator
echo -n "Uploading test object... "

temp_data=$(tmpfile)
dd if=/dev/urandom of="$temp_data" bs=1M count=10 &> /dev/null

runcurl \
  --header \"X-Auth-Token: "$auth_token"\" \
  --request PUT \
  --data-binary @"$temp_data" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:${SWIFT_STORAGE_PORT}/v1/AUTH_${project_id}/${SWIFT_CONTAINER}/${SWIFT_OBJECT}"

#
# Get Information About Container
#
separator
echo -n "Getting information about container... "

runcurl \
  --header \"X-Auth-Token: "$auth_token"\" \
  --head \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:${SWIFT_STORAGE_PORT}/v1/AUTH_${project_id}/${SWIFT_CONTAINER}"

#
# Get Information About Object
#
separator
echo -n "Getting information about object... "

runcurl \
  --header \"X-Auth-Token: "$auth_token"\" \
  --head \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:${SWIFT_STORAGE_PORT}/v1/AUTH_${project_id}/${SWIFT_CONTAINER}/${SWIFT_OBJECT}"

#
# Download Test Object
#
separator
echo -n "Downloading test object... "

runcurl \
  --header \"X-Auth-Token: "$auth_token"\" \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:${SWIFT_STORAGE_PORT}/v1/AUTH_${project_id}/${SWIFT_CONTAINER}/${SWIFT_OBJECT}"

#
# Revoke Authentication Token
#
separator
echo -n "Revoking authentication token... "

runcurl \
  --header \"X-Auth-Token: "$auth_token"\" \
  --header \"X-Subject-Token: "$auth_token"\" \
  --request DELETE \
  "${SWIFT_PROTOCOL}://${SWIFT_IP}:${SWIFT_AUTH_PORT}/v3/auth/tokens"

echo "All tests successful! 🎉 Exiting..."

exit 0