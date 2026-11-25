#!/usr/bin/env bash
# Deletes the review-wait Agent, then its Configuration. Leaves the model
# credential source, its Secret and the Namespace: delete those with
# occ credential-source delete, occ secret delete and occ namespace delete.
#
#   OCC_URL=... OCC_SERVICE_KEY_FILE=... OCC_NAMESPACE=... ./delete.sh
set -euo pipefail                                                      # stop on the first failing command or unset variable
: "${OCC_URL:?}" "${OCC_SERVICE_KEY_FILE:?}" "${OCC_NAMESPACE:?}"      # require the endpoint, the key file and the Namespace ID
OCC=${OCC:-occ}                                                        # the occ binary to run
STATE_DIR=${STATE_DIR:-$HOME/.local/state/oce/agent-samples}           # where deploy.sh recorded the IDs
AGENT_NAME=${AGENT_NAME:-review-wait}                                 # which record to read
record="$STATE_DIR/$AGENT_NAME.json"                                   # the record file
agent_id=$(jq -er .agentId "$record")                                  # the Agent to delete
configuration_id=$(jq -er .configurationId "$record")                  # its Configuration, deleted after the Agent

$OCC agent delete "$agent_id"                                          # start deletion: OCE stops the Pods and removes runtime state
echo "Deletion accepted; waiting for the Agent to disappear..." >&2
while $OCC agent get "$agent_id" > /dev/null 2>&1; do sleep 5; done    # wait until a read no longer finds it
$OCC configuration delete "$configuration_id"                          # now unreferenced, the Configuration can go
rm -f "$record"                                                        # forget the IDs
echo "Deleted Agent $agent_id and Configuration $configuration_id." >&2
