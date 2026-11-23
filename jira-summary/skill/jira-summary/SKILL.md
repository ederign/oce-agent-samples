---
name: jira-summary
description: Fetch one Jira issue by key and write a short markdown summary of it to artifacts/<KEY>-summary.md.
metadata: {"openclaw": {"requires": {"bins": ["python3"]}}}
---

# Jira issue summary

Use this skill when the user gives a Jira issue key (for example `RHAIRFE-1234`)
and asks for a summary.

1. Fetch the issue. Run this as one command, exactly as written, with the key
   as the script's only argument:

   ```sh
   set -a; [ -f /sandbox/enterprise/jira.env ] && . /sandbox/enterprise/jira.env; set +a; python3 {baseDir}/scripts/fetch_issue.py <KEY>
   ```

   The first part loads the non-secret Jira settings (`JIRA_SERVER`,
   `JIRA_USER`) when the workspace has them. Never print that file or any
   environment variable. The script prints the issue as JSON on stdout.

2. If the script exits with code 2, Jira credentials are not available to it.
   Tell the user which variables it named and stop. Do not ask for a token in
   chat and do not try another way to reach Jira.

3. If it exits with code 1, report its stderr line and stop.

4. Otherwise write `artifacts/<KEY>-summary.md` in the working directory:

   ```markdown
   # <KEY>: <summary>

   | Type | Status | Priority | Assignee |
   | --- | --- | --- | --- |
   | <type> | <status> | <priority> | <assignee> |

   ## What it asks for

   Three to five sentences from the description, in plain words.

   ## Open questions

   Anything the description leaves unclear, as a short list. Write "None" if it is clear.
   ```

5. Reply with the file path and the "What it asks for" paragraph.

This skill only reads Jira. Never create, edit or comment on issues.
