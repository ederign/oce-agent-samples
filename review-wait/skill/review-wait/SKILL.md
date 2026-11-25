---
name: review-wait
description: Start three reviewers, two quick and one slow, wait for them once for up to 55 seconds, and report what the wait returned.
---

# Review wait

Use this skill when the user asks for a review. It starts three reviewer child
sessions and waits for them with one `subagents wait` call.

| Reviewer | Label | Work time |
| --- | --- | --- |
| 1 | `quick-1` | 5 seconds |
| 2 | `quick-2` | 5 seconds |
| 3 | `slow-3` | 45 seconds |

The wait allows 55 seconds, which is enough for all three.

## Steps

Follow these steps exactly. Make each tool call once. Do not retry a failed call.

1. Spawn the three reviewers in one batch, one `sessions_spawn` call each. If
   `sessions_spawn` is only reachable through `dispatch_action`, call
   `dispatch_action` with `id` `openclaw:core:sessions_spawn`. Pass only these
   two arguments:
   - `label`: the reviewer's label from the table. If the user gave a suffix,
     append it: `quick-1-<suffix>`.
   - `task`: the brief below, with `<label>` and `<seconds>` filled in from the table.

   ```text
   You are reviewer <label>. First run the shell command `sleep <seconds>` with exec. Then reply with exactly one line: "<label>: done after <seconds> s".
   ```

2. Note the `runId` of every accepted spawn exactly as returned, including any
   prefix such as `worker-session-spawn:`. If no spawn was accepted, skip to step 4.

3. Wait once: call `subagents` (through `dispatch_action` with `id`
   `openclaw:core:subagents` if needed) with
   `{"action": "wait", "runIds": [<every accepted runId>], "timeoutSeconds": 55}`.

4. Reply with this and nothing else:

   ```text
   Review wait result
   - <label>: <the reviewer's reply line, or "no reply: <the exact error or status you got>">
   (one line per reviewer)
   Wait: <the status and reason of the wait call, or its exact error>
   ```

   Report only what tool results gave you. Never guess a reply.
