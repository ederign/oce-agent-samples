#!/usr/bin/env bash
# Saves skill/jira-summary (SKILL.md and scripts/) to the deployed Agent's
# OpenClaw Skill Library (a new revision if it is already there) and shares it,
# so new sessions can select it.
# Runs the openclaw CLI inside the Agent's Gateway container, which already
# holds the Gateway's own credentials; nothing secret passes through here.
#
#   KUBECTL="kubectl --kubeconfig FILE" ./publish-skill.sh
set -euo pipefail                                                      # stop on the first failing command or unset variable
here=$(cd "$(dirname "$0")" && pwd)                                    # this folder, so the script runs from anywhere
: "${KUBECTL:?Set KUBECTL to a kubectl command line for the install cluster}"  # require a kubectl for the install's cluster
STATE_DIR=${STATE_DIR:-$HOME/.local/state/oce/agent-samples}           # where deploy.sh recorded the IDs
AGENT_NAME=${AGENT_NAME:-jira-summary}                                 # which record to read
agent_id=$(jq -er .agentId "$STATE_DIR/$AGENT_NAME.json")              # the Agent ID deploy.sh recorded

# shellcheck disable=SC2086
pod=$($KUBECTL get pods -A -l "openclaw.dev/agent=$agent_id" -o json | jq -er '
  [.items[] | select(.spec.containers[].name == "gateway")] | first
  | "\(.metadata.namespace) \(.metadata.name)"')                       # find this Agent's Gateway Pod as "k8s-namespace pod-name"
gateway() {                                                            # run a command in that Pod's gateway container
  # shellcheck disable=SC2086
  $KUBECTL exec -i -n ${pod% *} ${pod#* } -c gateway -- "$@"
}

bundle=/tmp/jira-summary-skill                                         # temporary copy location inside the container
gateway rm -rf "$bundle"                                               # clear any copy left by an earlier run
COPYFILE_DISABLE=1 tar --no-xattrs -C "$here/skill" -cf - jira-summary |
  gateway sh -c "mkdir -p $bundle && tar -C $bundle -xf -"             # copy the skill folder in, keeping executable bits; no macOS ._ metadata files
existing=$(gateway openclaw skills library list --json |
  jq -c '[.. | objects | select(.slug? == "jira-summary")] | first // empty')  # an earlier publish of this skill, if any
if [ -n "$existing" ]; then                                            # already in the library: save a new revision of it
  skill=$(gateway openclaw skills library update "$(jq -er .skillId <<<"$existing")" "$bundle/jira-summary" \
    --expected-revision "$(jq -er .revision <<<"$existing")" --json)  # replace the bundle; a conflicting revision is refused, never overwritten
else                                                                   # first publish: create it
  skill=$(gateway openclaw skills library create "$bundle/jira-summary" --slug jira-summary --json)  # save it as a Skill Library revision
fi
echo "$skill" | jq . >&2                                               # show what the Gateway stored
skill_id=$(jq -er '.skillId // .entry.skillId' <<<"$skill")            # the skill's stable ID
revision=$(jq -er '.revision // .entry.revision' <<<"$skill")          # the revision hash just saved
if [ "$(jq -r '.shared // false' <<<"${existing:-{\}}")" != true ]; then  # share once; an updated shared skill stays shared
  gateway openclaw skills library share "$skill_id" --expected-revision "$revision" --json | jq . >&2  # make it visible to other profiles, such as your console chat
fi
gateway rm -rf "$bundle"                                               # remove the temporary copy; the library keeps its own
