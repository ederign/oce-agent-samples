# oce-agent-samples

Small agents for OpenClaw Enterprise (OCE), one per folder. Each folder deploys
with the `occ` CLI and holds everything the agent needs: its Configuration,
instructions, skills and scripts.

| Sample | What it does |
| --- | --- |
| [jira-summary](jira-summary/) | Fetches one Jira issue by key and writes a short markdown summary. Reads Jira only. |
| [review-team](review-team/) | Spawns reviewer child sessions on an RFE, waits for their verdicts and writes one summary. Includes a local reproducer for four worker-session bugs. |
| [review-wait](review-wait/) | Spawns two quick reviewers and one slow one, waits once for 55 s and reports the result. Shows the 30 s cut-off of `subagents wait` on a dedicated worker. |
