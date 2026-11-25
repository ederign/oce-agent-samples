# review-wait

A dedicated OpenClaw Agent that starts three reviewer child sessions, waits for
them once, and reports what the wait returned. It shows that a `subagents wait`
made from a dedicated worker is cut off at 30 seconds, whatever `timeoutSeconds`
the agent asks for.

| Reviewer | Work time |
| --- | --- |
| `quick-1` | 5 s |
| `quick-2` | 5 s |
| `slow-3` | 45 s |

The coordinator waits with `timeoutSeconds: 55`, which covers all three.

## What you should see

On a dedicated worker the wait fails about 30 seconds after it starts with
`worker gateway-tool response timed out`. The two quick reviewers have already
finished by then, but the reply reports no result for any of them:

```text
Review wait result
- quick-1: no reply: worker gateway-tool response timed out
- quick-2: no reply: worker gateway-tool response timed out
- slow-3: no reply: worker gateway-tool response timed out
Wait: error: worker gateway-tool response timed out
```

The cause is in the OpenClaw runtime. The worker sends each Gateway tool call
with a 30 second deadline unless the tool declares a longer one, and
`subagents` does not. With that fixed, the same wait returns after about 45
seconds with all three replies.

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

## Deploy

```sh
export OCC_URL=... OCC_SERVICE_KEY_FILE=...
export OCC_NAMESPACE=$(./namespace.sh)
export MODEL_SOURCE_ID=$(OPENAI_API_KEY_FILE=... ./model-source.sh)
./deploy.sh
export KUBECTL="kubectl --kubeconfig FILE"
./publish-skill.sh
```

Then open the Agent UI, start a new chat with the `review-wait` skill selected,
and ask: "Run the review."

Child labels must be unique across the Agent's sessions, so a second run in a
new chat fails to spawn with `label already in use`. Give a suffix to avoid it:
"Run the review with suffix 2."

The only credential is the model key. `model-source.sh` reads it from a file
and stores it as a Namespace Secret.
