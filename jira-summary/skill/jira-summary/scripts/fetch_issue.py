#!/usr/bin/env python3
"""Fetch one Jira issue and print its main fields as JSON.

Usage:
    python3 fetch_issue.py PROJ-123

Environment variables:
    JIRA_SERVER  Jira server URL (e.g. https://mysite.atlassian.net)
    JIRA_USER    Jira username/email
    JIRA_TOKEN   Jira API token

Exit codes:
    0  Success
    1  API or network error
    2  Missing Jira credentials
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

FIELDS = "summary,status,issuetype,priority,assignee,reporter,labels,description"


def adf_to_text(node):
    """Flatten an Atlassian Document Format node to plain text, one block per line."""
    if isinstance(node, str):
        return node
    if not isinstance(node, dict):
        return ""
    if node.get("type") == "text":
        return node.get("text", "")
    if node.get("type") == "hardBreak":
        return "\n"
    inner = "".join(adf_to_text(child) for child in node.get("content", []))
    if node.get("type") in ("paragraph", "heading", "listItem", "codeBlock", "blockquote"):
        return inner + "\n"
    return inner


def fetch_issue(server, user, token, key):
    credentials = base64.b64encode(f"{user}:{token}".encode()).decode()
    url = f"{server.rstrip('/')}/rest/api/3/issue/{urllib.parse.quote(key)}?fields={FIELDS}"
    request = urllib.request.Request(
        url, headers={"Authorization": f"Basic {credentials}", "Accept": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read())


def name_of(field):
    return (field or {}).get("displayName") or (field or {}).get("name")


def main():
    if len(sys.argv) != 2:
        print("Usage: fetch_issue.py ISSUE-KEY", file=sys.stderr)
        return 1
    key = sys.argv[1]
    server, user, token = (os.environ.get(n) for n in ("JIRA_SERVER", "JIRA_USER", "JIRA_TOKEN"))
    missing = [n for n, v in (("JIRA_SERVER", server), ("JIRA_USER", user), ("JIRA_TOKEN", token)) if not v]
    if missing:
        print(f"Missing Jira credentials: {', '.join(missing)}", file=sys.stderr)
        return 2
    try:
        issue = fetch_issue(server, user, token, key)
    except urllib.error.HTTPError as e:
        print(f"Jira returned HTTP {e.code} for {key}", file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"Cannot reach Jira: {e.reason}", file=sys.stderr)
        return 1
    fields = issue.get("fields", {})
    print(json.dumps({
        "key": issue.get("key", key),
        "summary": fields.get("summary"),
        "type": name_of(fields.get("issuetype")),
        "status": name_of(fields.get("status")),
        "priority": name_of(fields.get("priority")),
        "assignee": name_of(fields.get("assignee")),
        "reporter": name_of(fields.get("reporter")),
        "labels": fields.get("labels", []),
        "description": adf_to_text(fields.get("description")).strip(),
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
