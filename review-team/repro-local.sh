#!/usr/bin/env bash
# Local reproducer for four worker-session bugs, using the review-team agent on
# plain OpenClaw: one Gateway and two paired node workers on this machine. It is
# not part of the occ deployment and talks to no OCE install.
#
# Each node gets its own HOME, TMPDIR, state dir and workspace, so it shares
# nothing with the Gateway except the Gateway-node protocol, like a remote worker.
# Every process runs under `env -i` with an allowlist.
#
#   OPENCLAW_SRC=<built openclaw checkout> OPENAI_API_KEY_FILE=<file> \
#   REPRO_STATE_DIR=<empty dir> [REPRO_PORT=19320] ./repro-local.sh start|act1|act2|act3|stop
#
#   start  Gateway on 127.0.0.1:$REPRO_PORT, node "review-wide" (8 slots), node "review-small" (1 slot)
#   act1   3 reviewers: the parent never gets their results (F1); the 55 s wait fails at 30 s (F2)
#   act2   same review again: every fixed label is "already in use" (F3)
#   act3   1 reviewer on the 1-slot node: "outcome unknown", the child row holds the real reason (F4)
#   stop   stop the Gateway and both nodes (state stays in $REPRO_STATE_DIR)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)                                    # this folder, so the script runs from anywhere
: "${OPENCLAW_SRC:?Set OPENCLAW_SRC to a built openclaw checkout}"     # source tree with dist/ built
: "${REPRO_STATE_DIR:?Set REPRO_STATE_DIR to a directory for all state}"  # everything this script writes goes here
PORT=${REPRO_PORT:-19320}                                              # Gateway port on loopback
PNPM=(npx -y pnpm@12.15.0 --silent)                                    # the pnpm version openclaw pins
gw=$REPRO_STATE_DIR/gateway                                            # Gateway state dir
node_bin=$(dirname "$(command -v node)")                               # Node 24 must be first on PATH
CLEANPATH="$node_bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

openai_key() {                                                         # the key, read from its file only when needed
  : "${OPENAI_API_KEY_FILE:?Set OPENAI_API_KEY_FILE to a file holding the OpenAI API key}"
  tr -d '\n' < "$OPENAI_API_KEY_FILE"
}

cli() {                                                                # openclaw CLI against this Gateway
  (cd "$OPENCLAW_SRC" && env -i HOME="$HOME" PATH="$CLEANPATH" TMPDIR="${TMPDIR:-/tmp}" \
    OPENCLAW_STATE_DIR="$gw" OPENCLAW_CONFIG_PATH="$gw/openclaw.json" OPENCLAW_GATEWAY_PORT="$PORT" \
    "${PNPM[@]}" openclaw "$@")
}

call() {                                                               # one Gateway RPC: call METHOD JSON
  cli gateway call "$1" --params "$2" --json --timeout 600000
}

wait_for_line() {                                                      # wait_for_line FILE PATTERN SECONDS
  local i
  for ((i = 0; i < $3; i++)); do
    grep -q "$2" "$1" 2>/dev/null && return 0
    sleep 1
  done
  echo "timed out waiting for '$2' in $1" >&2
  return 1
}

start_bg() {                                                           # start_bg NAME LOG CMD...: own process group, pid file
  set -m
  nohup "${@:3}" > "$2" 2>&1 &
  echo $! > "$REPRO_STATE_DIR/$1.pid"
  set +m
}

start_gateway() {
  mkdir -p -m 700 "$gw/workspace/skills"
  if [ ! -f "$gw/openclaw.json" ]; then
    # The agent's workspace: its AGENTS.md and the skill. It is a git repo with one
    # commit because a session placed on a node needs a session-owned worktree.
    cp "$here/AGENTS.md" "$gw/workspace/AGENTS.md"
    cp -R "$here/skill/review-team" "$gw/workspace/skills/review-team"
    git -C "$gw/workspace" init -q
    git -C "$gw/workspace" add -A
    git -C "$gw/workspace" -c user.name=review-team -c user.email=review-team@example.invalid commit -qm "review-team workspace"
    # The sample's Configuration with local overrides: loopback, a token, this workspace, pairing URL.
    jq --arg token "$(openssl rand -hex 16)" --arg url "http://127.0.0.1:$PORT" --arg ws "$gw/workspace" '
      .values
      | .gateway = {mode: "local", bind: "loopback", auth: {mode: "token", token: $token}}
      | .agents.defaults.workspace = $ws
      | .plugins.entries = {"device-pair": {config: {publicUrl: $url}}, bonjour: {enabled: false}}
    ' "$here/configuration.json" > "$gw/openclaw.json"
  fi
  # The key travels in the environment, never on a command line.
  export REPRO_OPENAI_KEY
  REPRO_OPENAI_KEY=$(openai_key)
  start_bg gateway "$REPRO_STATE_DIR/gateway.log" \
    bash -c 'cd "$1" && exec env -i HOME="$2" PATH="$3" TMPDIR="${4:-/tmp}" OPENAI_API_KEY="$REPRO_OPENAI_KEY" \
      OPENCLAW_STATE_DIR="$5" OPENCLAW_CONFIG_PATH="$5/openclaw.json" OPENCLAW_GATEWAY_PORT="$6" \
      npx -y pnpm@12.15.0 openclaw gateway run --port "$6"' _ \
    "$OPENCLAW_SRC" "$HOME" "$CLEANPATH" "${TMPDIR:-/tmp}" "$gw" "$PORT"
  unset REPRO_OPENAI_KEY
  wait_for_line "$REPRO_STATE_DIR/gateway.log" "http server listening" 180
  echo "Gateway listening on 127.0.0.1:$PORT"
}

start_node() {                                                         # start_node NAME SLOTS
  local home=$REPRO_STATE_DIR/$1 url
  mkdir -p -m 700 "$home/state" "$home/tmp"
  [ -f "$home/state/openclaw.json" ] ||
    jq -n --argjson slots "$2" '{nodeHost: {workerRuns: {capacity: $slots}}}' > "$home/state/openclaw.json"
  url=$(cli devices join-code --json | jq -er .joinUrl)                # single-use join code
  start_bg "$1" "$REPRO_STATE_DIR/$1.log" \
    bash -c 'cd "$1" && exec env -i HOME="$2" PATH="$3" TMPDIR="$2/tmp" \
      OPENCLAW_STATE_DIR="$2/state" OPENCLAW_CONFIG_PATH="$2/state/openclaw.json" \
      npx -y pnpm@12.15.0 --silent openclaw connect "$4" --session-host --display-name "$5"' _ \
    "$OPENCLAW_SRC" "$home" "$CLEANPATH" "$url" "$1"
  wait_for_line "$REPRO_STATE_DIR/$1.log" "gateway connected" 300
  echo "Node $1 connected ($2 worker slots)"
}

stop_all() {
  local name pid
  for name in review-small review-wide gateway; do
    [ -f "$REPRO_STATE_DIR/$name.pid" ] || continue
    pid=$(cat "$REPRO_STATE_DIR/$name.pid")
    kill -TERM -- "-$pid" 2>/dev/null || true                          # the whole process group
    rm -f "$REPRO_STATE_DIR/$name.pid"
    echo "stopped $name"
  done
}

new_parent() {                                                         # new_parent KEY NODE: create, place on NODE
  local device
  device=$(call node.list '{}' | jq -er --arg n "$2" '[.nodes[] | select(.displayName == $n and .connected)][0].nodeId')
  call sessions.create "$(jq -nc --arg k "$1" '{key: $k, agentId: "main", worktree: true}')" | jq -e .ok > /dev/null
  call sessions.dispatch "$(jq -nc --arg k "$1" --arg d "$device" '{key: $k, deviceId: $d}')" |
    jq -r --arg n "$2" '"  parent placed on \($n): \(.placement.state // .error.message)"'
}

run_turn() {                                                           # run_turn KEY MESSAGE: one parent turn, waited
  local run="run-$(date +%s)-$RANDOM"
  call agent "$(jq -nc --arg k "$1" --arg m "$2" --arg r "$run" \
    '{sessionKey: $k, message: $m, idempotencyKey: $r, deliver: false}')" > /dev/null
  call agent.wait "$(jq -nc --arg r "$run" '{runId: $r, timeoutMs: 580000}')" |
    jq -r '"  parent turn: \(.status)"'
}

history() { call chat.history "$(jq -nc --arg k "$1" '{sessionKey: $k, limit: 200}')"; }

evidence() {                                                           # evidence KEY [CHILDREN_FILE]
  history "$1" | python3 -I "$here/repro-local-evidence.py" ${2:+--children "$2"}
}

review_prompt() {                                                      # review_prompt N PREFIX
  echo "Run a team review of the sample RFE with the review-team skill. N=$1, label prefix $2. Follow the skill's steps exactly: spawn, one wait, then the summary."
}

act1() {
  local key="agent:main:dashboard:review-act1-$(date +%s)" children=$REPRO_STATE_DIR/act1-children.json
  echo "== Act 1: three reviewers (F1, F2)"
  new_parent "$key" review-wide
  run_turn "$key" "$(review_prompt 3 reviewer)"
  evidence "$key" "$children"
  local parent_count last_done=0 label child line done_at
  parent_count=$(history "$key" | jq '.messages | length')
  echo "  waiting for the reviewers to finish (about 45 s each)..."
  while read -r label child; do
    line=""
    for _ in $(seq 1 40); do
      line=$(history "$child" | jq -r '[.messages[] | select(.role == "assistant")
        | {t: .timestamp, x: (.content | if type == "string" then . else (map(.text // "") | join("")) end)}
        | select(.x | test("reviewer-"))] | last | select(.) | "\(.t) \(.x)"')
      [ -n "$line" ] && break
      sleep 5
    done
    done_at=${line%% *}
    echo "  reviewer $label replied: ${line#* }"
    [ -n "$done_at" ] && [ "$done_at" -gt "$last_done" ] && last_done=$done_at
  done < <(jq -r '.[] | "\(.label) \(.key)"' "$children")
  sleep 20                                                             # give a completion turn time to start
  history "$key" | jq -r --argjson n "$parent_count" --argjson t "$last_done" '
    "  F1: parent messages after the last reviewer finished: \([.messages[] | select(.timestamp > $t)] | length)"
    + " (messages before: \($n), now: \(.messages | length))"'
}

act2() {
  local key="agent:main:dashboard:review-act2-$(date +%s)"
  echo "== Act 2: the same review again (F3)"
  new_parent "$key" review-wide
  run_turn "$key" "$(review_prompt 3 reviewer)"
  evidence "$key"
}

act3() {
  local key="agent:main:dashboard:review-act3-$(date +%s)"
  echo "== Act 3: one reviewer on the 1-slot node (F4)"
  new_parent "$key" review-small
  run_turn "$key" "$(review_prompt 1 capacity-reviewer)"
  evidence "$key"
  echo "  child rows of this parent:"
  call sessions.list '{"limit": 500}' | jq -r --arg p "$key" '.sessions[] | select(.parentSessionKey == $p) | .key' |
    while read -r child; do
      call sessions.describe "$(jq -nc --arg k "$child" '{key: $k}')" | jq -r '
        (.placement // .session.placement // {}) as $p
        | "    \(.session.label // .label // "?") \(.key // .session.key): placement=\($p.state) reason=\($p.terminalReason)"'
    done
}

case "${1:-}" in
  start) mkdir -p -m 700 "$REPRO_STATE_DIR"; start_gateway; start_node review-wide 8; start_node review-small 1 ;;
  act1) act1 ;;
  act2) act2 ;;
  act3) act3 ;;
  stop) stop_all ;;
  *) sed -n '2,17p' "$0"; exit 2 ;;
esac
