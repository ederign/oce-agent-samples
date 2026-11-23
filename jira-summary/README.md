# jira-summary

A dedicated OpenClaw Agent that fetches one Jira issue by key and writes a short
summary to `artifacts/<KEY>-summary.md`. It only reads Jira.

## Files

- `configuration.json`: the OpenClaw Configuration OCE stores for the Agent.
- `AGENTS.md`: the Agent's instructions, seeded into its workspace.
- `skill/jira-summary/`: the skill and its script, `scripts/fetch_issue.py`
  (standard library only). The script reads `JIRA_SERVER`, `JIRA_USER` and
  `JIRA_TOKEN` and exits 2 when any is missing.
- `namespace.sh`, `model-source.sh`, `deploy.sh`, `delete.sh`: create the
  Namespace, register the model credential, deploy and remove the Agent with `occ`.
- `publish-skill.sh`: saves the skill to the Agent's Skill Library and shares it.
- `install-workspace-skill.sh`: copies the skill into the worker workspace instead.
- `install-jira-settings.sh`: writes `JIRA_SERVER` and `JIRA_USER` (not secret)
  to `/sandbox/enterprise/jira.env` on the worker, where the skill loads them.

## Deploy

```sh
export OCC_URL=... OCC_SERVICE_KEY_FILE=...
export OCC_NAMESPACE=$(./namespace.sh)
export MODEL_SOURCE_ID=$(OPENAI_API_KEY_FILE=... ./model-source.sh)
./deploy.sh
KUBECTL="kubectl --kubeconfig FILE" ./publish-skill.sh
```

Then open the Agent UI and ask: "Summarize Jira issue <KEY>".

## Jira credentials

The skill runs on the Agent's dedicated worker. Without Jira settings the script
exits 2 and the Agent says which variables are missing.

- **Token:** keep it out of the sandbox. Register it as an OCE `bearer-token`
  credential source (`host: <your-site>.atlassian.net`, `env_var: JIRA_TOKEN`)
  and bind it to the Agent. The sandbox only holds a placeholder; OpenShell
  swaps in the real token on requests from `toolBinaries` to that host. The
  Installation must list the real Python path in `toolBinaries`
  (`/usr/bin/python3.11` in the runtime image, not the `python3` symlink).
- **Server and user:** not secret. Write them to the worker with
  `install-jira-settings.sh`. This file stands in for a way to set non-secret
  Agent environment on a worker, which OCE does not offer yet.

On a dedicated worker the OpenClaw runtime passes only an allowlist of
environment variables to tools, so `JIRA_TOKEN` also needs a runtime patch like
OCE's existing Google one (`deploy/runtime/openclaw-google-worker-placeholder.patch`).
Without it the script reports `JIRA_TOKEN` missing.
