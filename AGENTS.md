# Working in oce-agent-samples

Small agents for OpenClaw Enterprise (OCE). This repository is public.

## No credentials, ever

- Never commit a credential: API keys, Jira or GitHub tokens, OCC service keys,
  gateway passwords, kubeconfigs, private keys, `.env` files, or OpenShell
  placeholder values (`openshell:resolve:env:…`).
- Never commit personal or install-specific data: email addresses, local paths,
  hostnames of private installs, or OCC IDs (`ns_`, `agt_`, `cfg_`, `cs_`, `sec_`, `rev_`).
- Scripts take credentials only as paths to files outside the repository or as
  OCE Secret and credential source IDs passed in environment variables. They
  never print a credential and never pass one as a command-line argument.
- Before every commit, read the staged diff and search it for the patterns
  above. If anything matches, stop and tell the maintainer.

## Layout

One sample per top-level folder. Each folder holds:

- `README.md`: what the agent does, its files, how to deploy it, which
  credentials it needs and how to supply them.
- `configuration.json`: the OpenClaw Configuration OCE stores.
- `AGENTS.md`: the agent's own instructions (seeded into its workspace; not
  instructions for working in this repository).
- `skill/<name>/`: skills and their scripts.
- Shell scripts that deploy and remove the agent with the `occ` CLI, reading
  their inputs from environment variables.

Add each new sample to the table in the root `README.md`.

## Commits

Sign off every commit (`git commit -s`). Do not push without the maintainer's
approval.
