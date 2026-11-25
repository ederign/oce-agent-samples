#!/usr/bin/env bash
# Prints every subagents wait call of a review-wait run, read from the Agent's
# Gateway transcript: which reviewer, the timeout asked for, how long the call
# really took and what it returned. Then prints when each reviewer finished,
# measured from the first wait for it. The model's own reply can leave out a
# failed call; the transcript cannot.
#
#   KUBECTL="kubectl --kubeconfig FILE" ./evidence.sh [SESSION_KEY]
#
# Without SESSION_KEY it reads the newest coordinator session of the Agent.
set -euo pipefail                                                      # stop on the first failing command or unset variable
: "${KUBECTL:?Set KUBECTL to a kubectl command line for the install cluster}"  # require a kubectl for the install's cluster
STATE_DIR=${STATE_DIR:-$HOME/.local/state/oce/agent-samples}           # where deploy.sh recorded the IDs
AGENT_NAME=${AGENT_NAME:-review-wait}                                  # which record to read
agent_id=$(jq -er .agentId "$STATE_DIR/$AGENT_NAME.json")              # the Agent ID deploy.sh recorded

# shellcheck disable=SC2086
pod=$($KUBECTL get pods -A -l "openclaw.dev/agent=$agent_id" -o json | jq -er '
  [.items[] | select(.spec.containers[].name == "gateway")] | first
  | "\(.metadata.namespace) \(.metadata.name)"')                       # find this Agent's Gateway Pod as "k8s-namespace pod-name"
call() {                                                               # one Gateway RPC inside that Pod: call METHOD JSON
  # shellcheck disable=SC2086
  $KUBECTL exec -i -n ${pod% *} ${pod#* } -c gateway -- openclaw gateway call "$1" --params "$2" --json
}

sessions=$(call sessions.list '{"limit": 200}')                        # every session, with created and ended times
key=${1:-$(jq -er '[.sessions[] | select(.key | test("^agent:main:dashboard:") and (test(":cloud-") | not))]
  | sort_by(.createdAt) | last | .key' <<<"$sessions")}                # newest coordinator: a dashboard session that is not a child
history=$(call chat.history "$(jq -nc --arg k "$key" '{sessionKey: $k, limit: 500}')")  # its transcript
echo "Session $key"

evidence() {                                                           # evidence PART: waits (a table) or finished (one line per reviewer)
  jq -r --arg part "$1" --argjson sessions "$sessions" '
  def inner: (fromjson? // null) as $j                                 # unwrap dispatch_action: the tool text inside its envelope
    | if ($j | type) == "object" and ($j.result.content[0].text? != null) then $j.result.content[0].text else . end;
  def payload: (.content[0].text // "") | inner | (fromjson? // .);    # a result as JSON when it is JSON, else its text
  ([.messages[] | select(.role == "toolResult") | {key: .toolCallId, value: {t: .timestamp, r: payload}}]
    | from_entries) as $results
  | [.messages[] | select(.role == "assistant") | .timestamp as $t
      | (.content // [])[] | select(type == "object" and .type == "toolCall")
      | {id, t: $t,
         tool: (if .name == "dispatch_action" then (.arguments.id | sub("^openclaw:core:"; "")) else .name end),
         args: (if .name == "dispatch_action" then .arguments.args else .arguments end)}
      | . + {res: $results[.id]}] as $calls
  | ([$calls[] | select(.tool == "sessions_spawn") | .res.r | objects | select(.runId)
      | {key: .runId, value: .childSessionKey}] | from_entries) as $child   # runId -> child session key
  | ([$sessions.sessions[] | {key, value: {label, endedAt}}] | from_entries) as $info
  | [$calls[] | select(.tool == "subagents" and .args.action == "wait")] as $waits
  | if $part == "waits" then ($waits[] | ($child[.args.runIds[0]] // "?") as $c
      | [($info[$c].label // "?"), (if .args.timeoutSeconds == null then "timeout default" else "timeout \(.args.timeoutSeconds)s" end),
         (if .res then "\((.res.t - .t) / 1000 * 10 | round / 10)s" else "no result" end),
         (.res.r | if type == "object" then "\(.status), \(.reason // .error // "")"
                   else "ERROR \(tostring | .[0:60])" end)] | join("\t"))
    else ($waits | group_by(.args.runIds[0])[] | first as $w | ($child[$w.args.runIds[0]] // "?") as $c
      | select($info[$c].endedAt)
      | (($info[$c].endedAt - $w.t) / 1000 * 10 | round / 10) as $d
      | if $d < 0 then "\($info[$c].label) finished \(-$d)s before its first wait started"
        else "\($info[$c].label) finished \($d)s after its first wait started" end) end
' <<<"$history"
}

evidence waits | column -t -s "$(printf '\t')"                         # one row per wait call
echo
evidence finished                                                      # when each reviewer really finished
