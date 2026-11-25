"""Prints the evidence of one review-team act from a chat.history reply.

Reads the parent session's chat.history JSON on stdin and prints each
sessions_spawn and subagents call with its result. With --children FILE it
also writes the accepted children (label, childSessionKey) to FILE as JSON.
"""

import json
import sys


def parse_json(text):
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        return None


def text_of(content):
    if isinstance(content, str):
        return content
    return "".join(part.get("text", "") for part in content or [] if isinstance(part, dict))


def unwrap_call(call):
    """Returns (tool name, arguments), looking through dispatch_action."""
    name, args = call.get("name"), call.get("arguments") or {}
    if name == "dispatch_action":
        inner = str(args.get("id", ""))
        return inner.split(":")[-1], args.get("args") or {}
    return name, args


def unwrap_result(text):
    """Returns the tool's own JSON result, looking through dispatch_action's envelope."""
    outer = parse_json(text)
    if isinstance(outer, dict) and isinstance(outer.get("result"), dict):
        inner = parse_json(text_of(outer["result"].get("content")))
        return inner if inner is not None else outer
    return outer if outer is not None else {"raw": text}


def main():
    children_file = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--children" else None
    messages = json.load(sys.stdin).get("messages", [])
    calls = {}
    for message in messages:
        if message.get("role") != "assistant" or isinstance(message.get("content"), str):
            continue
        for part in message.get("content") or []:
            if part.get("type") == "toolCall":
                calls[part["id"]] = (message.get("timestamp"), *unwrap_call(part))
    children = []
    for message in messages:
        if message.get("role") != "toolResult" or message.get("toolCallId") not in calls:
            continue
        called_at, name, args = calls[message["toolCallId"]]
        result = unwrap_result(text_of(message.get("content")))
        if name == "sessions_spawn":
            label = args.get("label", "?")
            if result.get("status") == "accepted":
                children.append({"label": label, "key": result.get("childSessionKey")})
                print(f"  spawn {label}: accepted  runId={result.get('runId')}")
            else:
                print(f"  spawn {label}: {result.get('status', 'error')}  error={result.get('error')!r}")
                if result.get("childSessionKey"):
                    print(f"        childSessionKey={result['childSessionKey']}")
        elif name == "subagents":
            elapsed = (message.get("timestamp", 0) - (called_at or 0)) / 1000
            asked = args.get("timeoutSeconds")
            summary = result.get("error") or f"status={result.get('status')} reason={result.get('reason')}"
            print(f"  subagents {args.get('action')}: asked timeoutSeconds={asked}, answered after {elapsed:.1f} s: {summary!r}")
    final = next(
        (m for m in reversed(messages) if m.get("role") == "assistant" and text_of(m.get("content")).strip()),
        None,
    )
    if final:
        print("  parent reply:")
        for line in text_of(final["content"]).strip().splitlines():
            print(f"    | {line}")
    if children_file:
        with open(children_file, "w", encoding="utf-8") as handle:
            json.dump(children, handle)


if __name__ == "__main__":
    main()
