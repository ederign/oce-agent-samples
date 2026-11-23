#!/usr/bin/env bash
# Creates and deploys the jira-summary Agent with the occ CLI only:
# one Configuration, one Agent (seeded with AGENTS.md), one guarded first deployment.
#
#   OCC_URL=... OCC_SERVICE_KEY_FILE=... OCC_NAMESPACE=... MODEL_SOURCE_ID=cs_... ./deploy.sh
#
# OCC_NAMESPACE is the ID namespace.sh printed; MODEL_SOURCE_ID is the source
# model-source.sh registered in that Namespace. The IDs of
# what this creates go to $STATE_DIR/jira-summary.json; publish-skill.sh and
# delete.sh read them from there.
set -euo pipefail                                                      # stop on the first failing command or unset variable
umask 077                                                              # files this script writes are readable only by you
here=$(cd "$(dirname "$0")" && pwd)                                    # this folder, so the script runs from anywhere
: "${OCC_URL:?}" "${OCC_SERVICE_KEY_FILE:?}" "${OCC_NAMESPACE:?}"      # require the endpoint, the key file and the Namespace ID
: "${MODEL_SOURCE_ID:?Set MODEL_SOURCE_ID to a ready model credential source}"  # require the model credential source
OCC=${OCC:-occ}                                                        # the occ binary to run
STATE_DIR=${STATE_DIR:-$HOME/.local/state/oce/agent-samples}           # where the IDs of created objects are recorded
AGENT_NAME=${AGENT_NAME:-jira-summary}                                 # the Agent's name in OCE
record="$STATE_DIR/$AGENT_NAME.json"                                   # the record file for this Agent
mkdir -p "$STATE_DIR"                                                  # create the record folder if needed
[ ! -e "$record" ] || { echo "$record exists: this Agent is already deployed. Run delete.sh first." >&2; exit 1; }  # never deploy twice
tmp=$(mktemp -d)                                                       # scratch folder for the Agent request document
trap 'rm -rf "$tmp"' EXIT                                              # delete it when the script ends

# 1. Configuration: the native OpenClaw document, stored by OCE. Not tied to an Agent yet.
configuration=$($OCC configuration create --file "$here/configuration.json" -o json)  # POST the Configuration
configuration_id=$(jq -er .id <<<"$configuration")                     # its ID, cfg_...
generation=$(jq -er .generation <<<"$configuration")                   # its version counter, needed by the next step
echo "Configuration $configuration_id (generation $generation)" >&2

# 2. Agent: a draft that points at the Configuration. Nothing runs yet.
# nativeAdmin prepares the Configuration for browser chat, which bumps its generation.
jq -n --arg name "$AGENT_NAME" --arg cfg "$configuration_id" --argjson gen "$generation" \
  --arg source "$MODEL_SOURCE_ID" --rawfile agents "$here/AGENTS.md" '
  {name: $name, configurationId: $cfg, executionMode: "dedicated",
   nativeAdmin: true, expectedConfigurationGeneration: $gen,
   harnessAuth: {method: "credential_source", sourceId: $source},
   credentialSources: [{sourceId: $source}],
   initialWorkspaceFiles: {"AGENTS.md": $agents}}' > "$tmp/agent.json"  # build the Agent document: worker mode, browser chat, model source, AGENTS.md
agent_id=$($OCC agent create --file "$tmp/agent.json" -o json | jq -er .id)  # POST the Agent draft; keep its ID, agt_...
echo "Agent $agent_id" >&2
jq -n --arg ns "$OCC_NAMESPACE" --arg agent "$agent_id" --arg cfg "$configuration_id" \
  --arg source "$MODEL_SOURCE_ID" \
  '{namespaceId: $ns, agentId: $agent, configurationId: $cfg, modelSourceId: $source}' > "$record"  # record the IDs now, so delete.sh works even if deploy fails

# 3. First deployment: freezes the Configuration generation we just read into an
# immutable revision and asks the worker to start it.
generation=$($OCC configuration get "$configuration_id" -o json | jq -er .generation)  # re-read: nativeAdmin changed the Configuration
revision_id=$($OCC agent deploy-first "$agent_id" --configuration "$configuration_id" \
  --generation "$generation" --key "$AGENT_NAME-first" -o json | jq -er .revisionId)  # deploy exactly that generation, once; keep the revision ID
jq --arg rev "$revision_id" '.revisionId = $rev' "$record" > "$tmp/record" && cp "$tmp/record" "$record"  # add the revision ID to the record
echo "Revision $revision_id: waiting for deployment (a few minutes)..." >&2

for _ in $(seq 1 60); do                                               # poll for up to 10 minutes
  status=$($OCC agent deployment-status "$agent_id" "$revision_id" -o json | jq -er .status)  # read the revision's deployment status
  case "$status" in
    succeeded) break ;;                                                # running: done
    failed) $OCC agent deployment-status "$agent_id" "$revision_id" >&2; exit 1 ;;  # failed: print the error table and stop
  esac
  sleep 10                                                             # still deploying: wait and read again
done
[ "$status" = succeeded ] || { echo "Timed out; last status: $status" >&2; exit 1; }  # never succeeded within the wait
echo "Deployed. Record: $record" >&2
