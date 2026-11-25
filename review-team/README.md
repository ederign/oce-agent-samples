# review-team

A small RFE-style coordinator. It spawns `N` reviewer child sessions with fixed
labels (`reviewer-1` to `reviewer-N`). Each reviewer gives a one-line verdict on
a short RFE that ships in the skill. The coordinator waits for them once with
`subagents wait` (`timeoutSeconds: 55`) and replies with one summary.

It has the same shape as our real coordinators (RFE Creator, Strat Creator,
Epic Creator), at a size where every step is visible.

## Files

- `configuration.json`: the OpenClaw Configuration OCE stores for the Agent
  (gpt-4.1, browser and web fetch off).
- `AGENTS.md`: the Agent's instructions, seeded into its workspace.
- `skill/review-team/SKILL.md`: the RFE text, the reviewer brief and the
  coordinator's steps. No scripts. Each reviewer runs `sleep 45` before its
  verdict to stand in for a real review, so the coordinator is still waiting
  after 30 seconds.
- `repro-local.sh` and `repro-local-evidence.py`: a local reproducer, described
  below.

## Deploy on OCE

Not scripted yet. It will follow `jira-summary`: `namespace.sh`,
`model-source.sh`, `deploy.sh`, then `publish-skill.sh` or
`install-workspace-skill.sh` for the skill. No credentials beyond the model
source are needed.

## Local reproducer (not part of the occ layout)

`repro-local.sh` is not an OCE deployment script. It runs this agent on plain
OpenClaw built from source, on one machine, to show four bugs in sessions
placed on a node worker. It talks to no OCE install.

It starts one Gateway and two paired node workers: `review-wide` with 8 worker
slots and `review-small` with 1. Each node has its own HOME, TMPDIR, state dir
and workspace, so it shares nothing with the Gateway except the Gateway-node
protocol, the way an OCE worker on another host would. Every process runs under
`env -i` with an allowlist of variables. Only the Gateway gets the OpenAI key.

Requirements: Node 24 first on `PATH`, `jq`, `python3`, `git`, and an openclaw
checkout already built with `pnpm install` and `pnpm build`.

```sh
export OPENCLAW_SRC=/path/to/openclaw          # built checkout
export OPENAI_API_KEY_FILE=/path/to/key-file   # read only by the script, never printed
export REPRO_STATE_DIR=/path/to/empty-dir      # all state and logs
export REPRO_PORT=19320                        # optional; Gateway port on loopback

./repro-local.sh start   # Gateway and both nodes, about a minute
./repro-local.sh act1    # about 2 minutes
./repro-local.sh act2
./repro-local.sh act3
./repro-local.sh stop
```

Each act creates a new coordinator session, places it on a node, runs one
turn, and prints the tool results from the transcript:

| Act | What it does | What it shows |
| --- | --- | --- |
| `act1` | 3 reviewers on `review-wide` | The 55 s `subagents wait` fails after about 30 s with `worker gateway-tool response timed out` (F2). The reviewers finish, but the coordinator never gets a turn with their results (F1). |
| `act2` | The same review in a new session | Every spawn fails with `label already in use: reviewer-1` and so on. Labels clash across sessions of the agent (F3). |
| `act3` | 1 reviewer on `review-small`, label prefix `capacity-reviewer` | The coordinator holds the only slot. The spawn returns `Worker session operation outcome is unknown; it was not replayed`, while the child row records `device worker is at capacity` (F4). |

Act 3 uses its own label prefix so that the clash from act 2 does not hide
the capacity error.

`stop` leaves `REPRO_STATE_DIR` in place. Delete it to start over: a second
`act1` on the same state fails with the act 2 clash.
