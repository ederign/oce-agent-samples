#!/usr/bin/env bash
# Writes the non-secret Jira settings (JIRA_SERVER, JIRA_USER) to
# /sandbox/enterprise/jira.env on the deployed Agent's dedicated worker, where the
# jira-summary skill loads them. The Jira token is not written here: bind it to
# the Agent as an OCE credential source so the sandbox only holds a placeholder.
# Run again after the worker's workspace is replaced; OCE does not track this file.
#
#   JIRA_SERVER=https://your-site.atlassian.net JIRA_USER=you@example.com \
#   KUBECTL="kubectl --kubeconfig FILE" ./install-jira-settings.sh
set -euo pipefail                                                      # stop on the first failing command or unset variable
: "${KUBECTL:?Set KUBECTL to a kubectl command line for the install cluster}"  # require a kubectl for the install's cluster
: "${JIRA_SERVER:?Set JIRA_SERVER to the Jira site URL}"                 # require the Jira site
: "${JIRA_USER:?Set JIRA_USER to the Jira account email}"                # require the account the token belongs to
STATE_DIR=${STATE_DIR:-$HOME/.local/state/oce/agent-samples}           # where deploy.sh recorded the IDs
AGENT_NAME=${AGENT_NAME:-jira-summary}                                 # which record to read
WORKSPACE=${WORKSPACE:-/sandbox/enterprise}                            # the Agent workspace inside the worker Sandbox
agent_id=$(jq -er .agentId "$STATE_DIR/$AGENT_NAME.json")              # the Agent ID deploy.sh recorded

# shellcheck disable=SC2086
pod=$($KUBECTL get pods -A -l "openclaw.dev/agent=$agent_id" -o json | jq -er '
  [.items[] | select(.spec.containers[].name == "agent")] | first
  | "\(.metadata.namespace) \(.metadata.name)"')                       # find this Agent's worker Sandbox Pod as "k8s-namespace pod-name"

# shellcheck disable=SC2086
printf 'JIRA_SERVER=%s\nJIRA_USER=%s\n' "$JIRA_SERVER" "$JIRA_USER" |
  $KUBECTL exec -i -n ${pod% *} ${pod#* } -c agent -- \
    sh -c "umask 077 && cat > $WORKSPACE/jira.env"                     # write the file readable only by the sandbox user
echo "Wrote $WORKSPACE/jira.env on ${pod#* } (JIRA_SERVER, JIRA_USER)." >&2
