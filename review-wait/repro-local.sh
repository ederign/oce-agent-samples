#!/usr/bin/env bash
# Local before-and-after reproducer for the 30 second subagents wait cut-off on
# a dedicated worker, on plain OpenClaw: one Gateway and one paired node worker
# on this machine. It is not part of the occ deployment and talks to no OCE install.
#
# The node gets its own HOME, TMPDIR, state dir and workspace, so it shares
# nothing with the Gateway except the Gateway-node protocol, like a remote worker.
# Every process runs under `env -i` with an allowlist.
#
#   OPENCLAW_SRC=<built openclaw checkout> OPENAI_API_KEY_FILE=<file> \
#   REPRO_STATE_DIR=<empty dir> [REPRO_PORT=19330] ./repro-local.sh start|gateway|worker|stop
#
#   start    Gateway on 127.0.0.1:$REPRO_PORT and node "wait-worker"
#   gateway  agent on the Gateway: a child sleeps 35 s, the agent waits up to 55 s
#   worker   the same, with the agent placed on the node worker
#   stop     stop the Gateway and the node (state stays in $REPRO_STATE_DIR)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)                                    # this folder, so the script runs from anywhere
: "${OPENCLAW_SRC:?Set OPENCLAW_SRC to a built openclaw checkout}"     # source tree with dist/ built
: "${REPRO_STATE_DIR:?Set REPRO_STATE_DIR to a directory for all state}"  # everything this script writes goes here
PORT=${REPRO_PORT:-19330}                                              # Gateway port on loopback
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
  mkdir -p -m 700 "$gw/workspace"
  if [ ! -f "$gw/openclaw.json" ]; then
    # A session placed on a node needs a session-owned worktree, so the workspace is a git repo.
    git -C "$gw/workspace" init -q
    git -C "$gw/workspace" -c user.name=review-wait -c user.email=review-wait@example.invalid \
      commit -q --allow-empty -m "review-wait workspace"
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

start_node() {
  local home=$REPRO_STATE_DIR/wait-worker url
  mkdir -p -m 700 "$home/state" "$home/tmp"
  url=$(cli devices join-code --json | jq -er .joinUrl)                # single-use join code
  start_bg wait-worker "$REPRO_STATE_DIR/wait-worker.log" \
    bash -c 'cd "$1" && exec env -i HOME="$2" PATH="$3" TMPDIR="$2/tmp" \
      OPENCLAW_STATE_DIR="$2/state" OPENCLAW_CONFIG_PATH="$2/state/openclaw.json" \
      npx -y pnpm@12.15.0 --silent openclaw connect "$4" --session-host --display-name wait-worker' _ \
    "$OPENCLAW_SRC" "$home" "$CLEANPATH" "$url"
  wait_for_line "$REPRO_STATE_DIR/wait-worker.log" "gateway connected" 300
  echo "Node wait-worker connected"
}

stop_all() {
  local name pid
  for name in wait-worker gateway; do
    [ -f "$REPRO_STATE_DIR/$name.pid" ] || continue
    pid=$(cat "$REPRO_STATE_DIR/$name.pid")
    kill -TERM -- "-$pid" 2>/dev/null || true                          # the whole process group
    rm -f "$REPRO_STATE_DIR/$name.pid"
    echo "stopped $name"
  done
}

run_case() {                                                           # run_case gateway|worker
  local place=$1 name key run history
  name="$place-$(date +%s)"                                            # labels must be unique across sessions
  key="agent:main:dashboard:wait-$name"
  run="run-$name"
  call sessions.create "$(jq -nc --arg k "$key" --argjson w "$([ "$place" = worker ] && echo true || echo false)" \
    '{key: $k, agentId: "main", worktree: $w}')" | jq -e .ok > /dev/null
  if [ "$place" = worker ]; then                                       # place the agent on the node worker
    local device
    device=$(call node.list '{}' | jq -er '[.nodes[] | select(.displayName == "wait-worker" and .connected)][0].nodeId')
    call sessions.dispatch "$(jq -nc --arg k "$key" --arg d "$device" '{key: $k, deviceId: $d}')" |
      jq -r '"  agent placed on wait-worker: \(.placement.state // .error.message)"'
  fi
  local message="Use sessions_spawn (directly or through dispatch_action with id openclaw:core:sessions_spawn) with only these arguments: label \"$name-child\", task \"Run the shell command \`sleep 35\` with exec, then reply with exactly: $name-child done\". Then call subagents (directly or through dispatch_action with id openclaw:core:subagents) once with {\"action\":\"wait\",\"runIds\":[<the runId you got>],\"timeoutSeconds\":55}. Then reply with the exact JSON or error the wait returned. Make each call once; do not retry."
  call agent "$(jq -nc --arg k "$key" --arg m "$message" --arg r "$run" \
    '{sessionKey: $k, message: $m, idempotencyKey: $r, deliver: false}')" > /dev/null
  call agent.wait "$(jq -nc --arg r "$run" '{runId: $r, timeoutMs: 240000}')" | jq -r '"  agent turn: \(.status)"'
  history=$(call chat.history "$(jq -nc --arg k "$key" '{sessionKey: $k, limit: 50}')")
  local ended="" _
  for _ in $(seq 1 12); do                                             # the child can outlive a failed wait: give it a minute
    ended=$(call sessions.list '{"limit": 500}' |
      jq -r --arg l "$name-child" '[.sessions[] | select(.label == $l)][0].endedAt // empty')
    [ -n "$ended" ] && break
    sleep 5
  done
  # The wait call, how long it really took, what it returned, and when the child finished.
  jq -r --arg ended "$ended" '
    def inner: (fromjson? // null) as $j
      | if ($j | type) == "object" and ($j.result.content[0].text? != null) then $j.result.content[0].text else . end;
    ([.messages[] | select(.role == "toolResult")
      | {key: .toolCallId, value: {t: .timestamp, r: ((.content[0].text // "") | inner)}}] | from_entries) as $res
    | [.messages[] | select(.role == "assistant") | .timestamp as $t | (.content // [])[]
        | select(type == "object" and .type == "toolCall" and ((.arguments | tostring) | test("\"wait\"")))
        | {id, t: $t}][]
    | "  wait took \((($res[.id].t - .t) / 100 | round) / 10) s: \($res[.id].r | .[0:160])",
      (if $ended != "" then "  child finished \(((($ended | tonumber) - .t) / 100 | round) / 10) s after the wait started" else empty end)
  ' <<<"$history"
}

case "${1:-}" in
  start) mkdir -p -m 700 "$REPRO_STATE_DIR"; start_gateway; start_node ;;
  gateway) echo "== Agent on the Gateway"; run_case gateway ;;
  worker) echo "== Agent on the node worker"; run_case worker ;;
  stop) stop_all ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac
