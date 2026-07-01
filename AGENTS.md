# Agent guide

This repository's agent instructions live in **[CLAUDE.md](CLAUDE.md)** — start there.

`CLAUDE.md` covers orientation (README + CONTRIBUTING are the source of truth),
when to read code, the canonical `make` commands, the non-negotiable module
boundaries, and which subagent to use for which task.

Project subagents in [`.claude/agents/`](.claude/agents/):

- **command-adder** — add a `container` command end-to-end (domain → port → adapter → mock → argv tests).
- **architecture-guardian** — read-only reviewer for layering, secrets, and boundary violations.
- **swiftui-view-builder** — build CapsuleUI views/inspectors/sheets to Capsule's house conventions.
- **test-author** — write tests across the unit / argv / golden-UI tiers.
