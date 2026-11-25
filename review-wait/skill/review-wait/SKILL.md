---
name: review-wait
description: Start a fast, a medium and a slow reviewer, wait for each with a different timeout, and report what every wait returned.
---

# Review wait

Use this skill when the user asks for a review. It starts three reviewer child
sessions and waits for each with `subagents wait`.

| Reviewer | Label | Work time | Wait | What the wait should return |
| --- | --- | --- | --- | --- |
| Fast | `fast` | 5 s | 20 s | completed, after about 5 s |
| Slow | `slow` | 120 s | 10 s | timeout, after 10 s |
| Medium | `medium` | 60 s | 55 s | completed, about 40 s into the wait |

A wait returns as soon as a child it waits for finishes, so each wait names one
reviewer. The waits run in the order of the table.

## Steps

Follow these steps exactly. Make each tool call once. Never retry a failed
call, and never repeat a wait: a failed call is the result this skill exists to
report.

Where a tool is only reachable through `dispatch_action`, call `dispatch_action`
with `id` `openclaw:core:<tool name>`.

1. Spawn the three reviewers, one `sessions_spawn` call each. Pass only these
   two arguments:
   - `label`: the label from the table. If the user gave a suffix, append it:
     `fast-<suffix>`.
   - `task`: the brief below, with `<label>` and `<seconds>` filled in from the table.

   ```text
   You are reviewer <label>. First run the shell command `sleep <seconds>` with exec. A line saying "cannot create /proc/self/oom_score_adj: Permission denied" is a harmless sandbox warning; the command still ran. Then reply with exactly one line: "<label>: done after <seconds> s".
   ```

   Note each `runId` and child session key exactly as returned, including any
   prefix such as `worker-session-spawn:`. If a spawn fails, do not spawn that
   reviewer again under another label: skip its wait and report the spawn error.

2. Wait for the fast reviewer: call `subagents` with
   `{"action": "wait", "runIds": [<fast runId>], "timeoutSeconds": 20}`.
   Then read its reply: call `sessions_history` with the fast reviewer's
   session key and take its last assistant line.

3. Wait for the slow reviewer: call `subagents` with
   `{"action": "wait", "runIds": [<slow runId>], "timeoutSeconds": 10}`.

4. Wait for the medium reviewer: call `subagents` with
   `{"action": "wait", "runIds": [<medium runId>], "timeoutSeconds": 55}`.
   If the user asked for the default wait, leave `timeoutSeconds` out:
   `{"action": "wait", "runIds": [<medium runId>]}`. The tool then waits its
   default 30 seconds.
   If it returned `completed`, read its reply with `sessions_history` as in
   step 2. If it returned an error, do not wait again and do not read the
   medium reviewer's history: go straight to step 5 and copy the error exactly.

   Make each wait a separate tool call, after the previous one has returned.
   Never put two waits in one batch.

5. Reply with this and nothing else:

   ```text
   Review wait result
   Wait calls, in the order you made them:
   - <reviewer label>, timeoutSeconds <n>: <the status and reason it returned, or its exact error>
   (one line for every `subagents` wait call you made, failed calls included)
   Replies:
   - <reviewer label>: <the reply line you read, or "none: <why>">
   ```

   Report only what tool results gave you. Never guess a reply, and never leave
   out a call that failed.
