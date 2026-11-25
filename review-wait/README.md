# review-wait

A dedicated OpenClaw Agent that starts three reviewer child sessions and waits
for each with `subagents wait`. It shows that a wait made from a dedicated
worker is cut off at 30 seconds, whatever `timeoutSeconds` the agent asks for.

| Reviewer | Work time | Wait | What the wait should return |
| --- | --- | --- | --- |
| `fast` | 5 s | 20 s | completed, after about 5 s |
| `slow` | 120 s | 10 s | timeout, after 10 s |
| `medium` | 60 s | 55 s | completed, about 40 s into the wait |

The waits run in that order. A wait returns as soon as a child it waits for
finishes, so each wait names one reviewer. The medium reviewer finishes after
30 seconds of waiting but well inside the 55 the agent asked for.

## What you should see

```text
Review wait result
Wait calls, in the order you made them:
- fast-1, timeoutSeconds 20: ok, completed
- slow-1, timeoutSeconds 10: ok, timeout
- medium-1, timeoutSeconds 55: The node disconnected before the turn finished. ...
Replies:
- fast-1: fast-1: done after 5 s
```

The first two wait calls are the tool working. The medium wait fails about 30
seconds after it starts, about 10 seconds before the medium reviewer finishes.
On OCE it fails with `The node disconnected before the turn finished`: the
worker drops its connection to the Gateway when the call times out, so the turn
may end there before the reply is written. The model may also wait for the
medium reviewer a second time and get `completed`; the reply lists every wait
call so that the failed one stays visible. The medium reviewer's own
session still shows it finished. On plain OpenClaw with a paired node the same
wait fails with `worker gateway-tool response timed out`.

The cause is in the OpenClaw runtime. The worker sends each Gateway tool call
with a 30 second deadline unless the tool declares a longer one, and
`subagents` does not. With that fixed, the medium wait returns
`ok, reason: completed` about 40 seconds in, with the medium reviewer's reply.

## Files

- `configuration.json`: the OpenClaw Configuration OCE stores for the Agent
  (gpt-4.1, browser and web fetch off).
- `AGENTS.md`: the Agent's instructions, seeded into its workspace.
- `skill/review-wait/SKILL.md`: the reviewer table, the reviewer brief and the
  coordinator's steps. No scripts. Each reviewer runs `sleep` to stand in for
  real work.
- `namespace.sh`, `model-source.sh`, `deploy.sh`, `delete.sh`: create the
  Namespace, register the model credential, deploy and remove the Agent with `occ`.
- `publish-skill.sh`: saves the skill to the Agent's Skill Library and shares it.
- `evidence.sh`: prints every wait call of a run from the Gateway's transcript,
  with the timeout asked for, how long the call really took and what it
  returned. The model's own reply can leave out a failed call.

## Deploy

```sh
export OCC_URL=... OCC_SERVICE_KEY_FILE=...
export OCC_NAMESPACE=$(./namespace.sh)
export MODEL_SOURCE_ID=$(OPENAI_API_KEY_FILE=... ./model-source.sh)
./deploy.sh
export KUBECTL="kubectl --kubeconfig FILE"
./publish-skill.sh
```

Then open the Agent UI (the Agent's page in the Console has an **Open Agent UI**
link), start a **New session** and ask: "Run the review." New sessions get the
published skill. The Agent's main session, which the Agent UI opens first, does
not.

To see what really happened, read the transcript:

```sh
KUBECTL="kubectl --kubeconfig FILE" ./evidence.sh
```

```text
fast-1    timeout 20s      2.6s   ok, completed
slow-1    timeout 10s      11.3s  ok, timeout
medium-1  timeout 55s      31.2s  ERROR The node disconnected before the turn finished. ...
medium-1  timeout 55s      16s    ok, completed

medium-1 finished 49.6s after its first wait started
```

The last line is the model waiting again on its own after the failure.

Ask for "the default wait" to make the medium wait without `timeoutSeconds`,
the way most agents call it: "Run the review with suffix 2 and the default
wait." It fails the same way: the Gateway waits its default 30 seconds, but the
worker starts its own 30 second clock first and gives up before the answer
arrives.

Child labels must be unique across the Agent's sessions, so a second run in a
new session fails to spawn with `label already in use`. Give a suffix to avoid
it: "Run the review with suffix 2."

The only credential is the model key. `model-source.sh` reads it from a file
and stores it as a Namespace Secret.
