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

Without Jira credentials the script exits 2 and the Agent says which variables
are missing. Keep the token out of the sandbox: register it as an OCE
`bearer-token` credential source with `env_var: JIRA_TOKEN` and bind it to the
Agent, so the sandbox only ever holds a placeholder.
