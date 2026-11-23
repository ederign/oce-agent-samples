#!/usr/bin/env bash
# Copies skill/jira-summary (SKILL.md and scripts/) into the deployed Agent's
# workspace on its dedicated worker, at /sandbox/enterprise/skills/jira-summary.
# OpenClaw discovers workspace skills on the worker and runs them there.
# Run again after the worker's workspace is replaced; OCE does not track these files.
#
#   KUBECTL="kubectl --kubeconfig FILE" ./install-workspace-skill.sh
set -euo pipefail                                                      # stop on the first failing command or unset variable
here=$(cd "$(dirname "$0")" && pwd)                                    # this folder, so the script runs from anywhere
: "${KUBECTL:?Set KUBECTL to a kubectl command line for the install cluster}"  # require a kubectl for the install's cluster
STATE_DIR=${STATE_DIR:-$HOME/.local/state/oce/agent-samples}           # where deploy.sh recorded the IDs
AGENT_NAME=${AGENT_NAME:-jira-summary}                                 # which record to read
WORKSPACE=${WORKSPACE:-/sandbox/enterprise}                            # the Agent workspace inside the worker Sandbox
agent_id=$(jq -er .agentId "$STATE_DIR/$AGENT_NAME.json")              # the Agent ID deploy.sh recorded

# shellcheck disable=SC2086
pod=$($KUBECTL get pods -A -l "openclaw.dev/agent=$agent_id" -o json | jq -er '
  [.items[] | select(.spec.containers[].name == "agent")] | first
  | "\(.metadata.namespace) \(.metadata.name)"')                       # find this Agent's worker Sandbox Pod as "k8s-namespace pod-name"
worker() {                                                             # run a command in that Pod's agent container
  # shellcheck disable=SC2086
  $KUBECTL exec -i -n ${pod% *} ${pod#* } -c agent -- "$@"
}

worker rm -rf "$WORKSPACE/skills/jira-summary"                         # replace any earlier copy completely
COPYFILE_DISABLE=1 tar --no-xattrs -C "$here/skill" -cf - jira-summary |
  worker sh -c "mkdir -p $WORKSPACE/skills && tar -C $WORKSPACE/skills -xf -"  # copy the skill folder in, keeping executable bits; no macOS ._ files
worker sh -c "cd $WORKSPACE/skills && find jira-summary -type f -exec ls -l {} +" >&2  # show what landed, with permissions
