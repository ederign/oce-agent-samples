#!/usr/bin/env bash
# Registers a Jira API token as an OCE `bearer-token` credential source, binds it
# to the deployed jira-summary Agent in place of any source already bound as
# JIRA_TOKEN, and deploys a new revision. The sandbox only ever holds a
# placeholder in JIRA_TOKEN; OpenShell swaps in the token on requests from the
# Installation's `toolBinaries` to the Jira host. The token is read from a file
# and never appears in a command argument or in output.
#
# New token, stored first as a Namespace Secret:
#   OCC_URL=... OCC_SERVICE_KEY_FILE=... OCC_NAMESPACE=... \
#   JIRA_SERVER=https://your-site.atlassian.net JIRA_TOKEN_FILE=... ./jira-source.sh
# Token already stored as a Namespace Secret (for example from the Console):
#   ... JIRA_SERVER=... JIRA_SECRET_ID=sec_... ./jira-source.sh
set -euo pipefail                                                      # stop on the first failing command or unset variable
umask 077                                                              # files this script writes are readable only by you
: "${OCC_URL:?}" "${OCC_SERVICE_KEY_FILE:?}" "${OCC_NAMESPACE:?}"      # require the endpoint, the key file and the Namespace ID
: "${JIRA_SERVER:?Set JIRA_SERVER to the Jira site URL}"                 # the site the token may be sent to
[ -n "${JIRA_TOKEN_FILE:-}${JIRA_SECRET_ID:-}" ] ||
  { echo "Set JIRA_TOKEN_FILE to a private file holding the token, or JIRA_SECRET_ID to an existing Secret" >&2; exit 1; }
OCC=${OCC:-occ}                                                        # the occ binary to run
SOURCE_NAME=${SOURCE_NAME:-jira}                                       # name for the Secret (when created) and the source
STATE_DIR=${STATE_DIR:-$HOME/.local/state/oce/agent-samples}           # where deploy.sh recorded the IDs
AGENT_NAME=${AGENT_NAME:-jira-summary}                                 # which record to read
record="$STATE_DIR/$AGENT_NAME.json"                                   # the record file for this Agent
agent_id=$(jq -er .agentId "$record")                                  # the Agent deploy.sh created
host=$(printf '%s' "$JIRA_SERVER" | sed -E 's#^https?://##; s#[/:].*$##' | tr 'A-Z' 'a-z')  # bare host name, as the source requires
tmp=$(mktemp -d)                                                       # private scratch folder for the request documents
trap 'rm -rf "$tmp"' EXIT                                              # delete it, with any token copy, when the script ends

# 1. The Secret that holds the token: create it from the file, or use the one given.
if [ -n "${JIRA_SECRET_ID:-}" ]; then
  jq -n --arg ns "$OCC_NAMESPACE" --arg id "$JIRA_SECRET_ID" \
    '{kind: "secret", namespaceId: $ns, id: $id}' > "$tmp/ref.json"    # reference to the existing Secret
else
  jq -Rs --arg name "$SOURCE_NAME" '{name: $name, value: gsub("\n"; "")}' \
    < "$JIRA_TOKEN_FILE" > "$tmp/secret.json"                          # build {name, value} from the token file, newline stripped
  $OCC secret create --file "$tmp/secret.json" -o json | jq -e '.ref' > "$tmp/ref.json"  # store it; keep only the metadata reference
fi

# 2. The source: deliver that Secret to the Jira host as a placeholder in JIRA_TOKEN.
jq -n --arg name "$SOURCE_NAME" --arg host "$host" --slurpfile ref "$tmp/ref.json" \
  '{name: $name, type: "bearer-token", config: {host: $host, env_var: "JIRA_TOKEN"},
    secrets: {token: $ref[0]}}' > "$tmp/source.json"                   # the source document
source_id=$($OCC credential-source create --file "$tmp/source.json" -o json | jq -er .id)  # register it with the gateway
echo "Source $source_id ($host, JIRA_TOKEN)" >&2

# 3. Bind it: keep the Agent's other sources, drop any other one that also projects JIRA_TOKEN.
agent=$($OCC agent get "$agent_id" -o json)                            # the Agent's current draft
keep='[]'
for id in $(jq -r '.credentialSources[].sourceId' <<<"$agent"); do     # each source bound today
  env_var=$($OCC credential-source get "$id" -o json | jq -r '.config.env_var // empty')
  [ "$env_var" = JIRA_TOKEN ] && { echo "Replacing $id, which also uses JIRA_TOKEN" >&2; continue; }
  keep=$(jq -c --arg id "$id" '. + [{sourceId: $id}]' <<<"$keep")      # keep it
done
jq --argjson keep "$keep" --arg source "$source_id" '
  {configurationId, backendId, harnessAuth, executionMode, gatewayManagedMode,
   credentialSources: ($keep + [{sourceId: $source}])}' <<<"$agent" > "$tmp/agent.json"  # the full draft PATCH requires
$OCC agent update "$agent_id" --file "$tmp/agent.json" -o json > /dev/null  # save the draft
jq --arg source "$source_id" '.jiraSourceId = $source' "$record" > "$tmp/record" && cp "$tmp/record" "$record"  # remember it

# 4. Deploy, so the worker starts with the placeholder.
revision_id=$($OCC agent deploy "$agent_id" -o json | jq -er '.revisionId // .id')  # new immutable revision
echo "Revision $revision_id: waiting for deployment..." >&2
for _ in $(seq 1 60); do                                               # poll for up to 10 minutes
  status=$($OCC agent deployment-status "$agent_id" "$revision_id" -o json | jq -er .status)
  case "$status" in
    succeeded) break ;;
    failed) $OCC agent deployment-status "$agent_id" "$revision_id" >&2; exit 1 ;;
  esac
  sleep 10
done
[ "$status" = succeeded ] || { echo "Timed out; last status: $status" >&2; exit 1; }
printf '%s\n' "$source_id"                                             # print the source ID for the record
