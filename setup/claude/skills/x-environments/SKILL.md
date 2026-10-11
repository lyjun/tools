---
name: x-environments
description: Execution rules for any context where commands must run through a wrapper instead of directly on host. Before any build/test/lint/git mutation in a project, or when the user references a remote host alias (e.g., "dev", "staging", 連到 dev, 登入開發機) or asks to SSH by account name (e.g., "SSH as ardge", 以 ardge 帳號 SSH), even without IP/credentials, consult routing.md `### x-environments` for the authoritative trigger list and load this skill if any condition matches. Per-environment procedures live in the reference files.
model: haiku
---

# Environment Execution Rules

Evaluate **each** condition independently against the current context. Load all reference files whose condition is met — multiple environments can apply simultaneously.

| Environment | Reference |
|-------------|-----------|
| Remote SSH with password credentials | `references/remote-ssh.md` |
| ARX host alias referenced (with or without credentials) | `references/arx-host-config.md` |
| DevContainer (`.devcontainer/`) | `references/devcontainer.md` |
| Docker operations | `references/docker.md` |
| Multipass VM (`multipass` commands) | `references/multipass.md` |
