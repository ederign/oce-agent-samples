---
name: review-team
description: Review the sample RFE with a team of reviewer child sessions, wait for their verdicts, and write one summary.
---

# Review team

Use this skill when the user asks for a team review of the sample RFE. The user
gives the number of reviewers `N` (default 3) and may give a label prefix
(default `reviewer`).

## The RFE

> **RFE: Export review results as CSV.** Reviewers want to download the
> verdicts of a review run as a CSV file with one row per reviewer and the
> columns `reviewer`, `verdict` and `reason`. The download button sits next to
> the run's summary. No new permissions are needed: anyone who can read the
> run can download its CSV.

## Steps

Follow these steps exactly. Make each tool call once. Do not retry a failed call.

1. Spawn `N` reviewers in one batch, one `sessions_spawn` call each. If
   `sessions_spawn` is only reachable through `dispatch_action`, call
   `dispatch_action` with `id` `openclaw:core:sessions_spawn`. Pass only these
   two arguments:
   - `label`: `<prefix>-<n>`, for example `reviewer-1`, `reviewer-2`, `reviewer-3`.
   - `task`: the reviewer brief below, with `<n>` replaced by the reviewer's number.

   Reviewer brief:

   ```text
   You are reviewer <n> of an RFE. First run the shell command `sleep 45` with exec; it stands for a careful read. Then reply with exactly one line: "reviewer-<n>: APPROVE - <reason>" or "reviewer-<n>: REJECT - <reason>", with a reason of at most 12 words. The RFE: Export review results as CSV. Reviewers want to download the verdicts of a review run as a CSV file with one row per reviewer and the columns reviewer, verdict and reason. The download button sits next to the run's summary. No new permissions are needed: anyone who can read the run can download its CSV.
   ```

2. Note the `runId` of every accepted spawn exactly as returned, including any
   prefix such as `worker-session-spawn:`. If no spawn was accepted, skip to step 4.

3. Wait for the reviewers once: call `subagents` (through `dispatch_action`
   with `id` `openclaw:core:subagents` if needed) with
   `{"action": "wait", "runIds": [<every accepted runId>], "timeoutSeconds": 55}`.

4. Reply with the summary and nothing else:

   ```text
   Review team summary
   - <label>: <the reviewer's verdict line, or "no verdict: <the exact error or status you got>">
   (one line per reviewer)
   Wait: <the status and reason of the wait call, or its exact error>
   ```

   Report only what tool results gave you. Never guess a verdict.
