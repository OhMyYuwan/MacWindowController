# AGENTS.md

This workspace is an ACP-managed macOS application project for `WinCtlManager`.

```
project/
├── AGENTS.md
├── acp-protocol/                    # ACP consumer package (read-only)
└── src/
    ├── .acp/
    │   ├── version.yaml
    │   ├── kernel/
    │   │   ├── requests/
    │   │   ├── plans/
    │   │   └── changes/
    │   ├── capability/
    │   └── support/
    ├── infra/
    └── (application source)
```

## Protocol Authority

- ACP behavioral authority: `acp-protocol/acp_agent_playbook.yaml`
- `acp-protocol/` is read-only and must not be mutated as project state.

## Project ACP State

- ACP entry point: `src/.acp/version.yaml`
- Support intake order:
  1. `src/.acp/support/AGENT.md`
  2. `src/.acp/support/PROJECT_MAP.yaml`
  3. `src/.acp/support/LOAD_RULES.yaml`
  4. `src/.acp/support/CHANGE_POLICY.yaml`
  5. `src/.acp/capability/capabilities.yaml`

## Mutation Rule

All mutation-oriented work must follow `Request → Plan → Change`.
Kernel objects are stored under `src/.acp/kernel/`.

## Working Constraints

- Do not broad-scan project source before ACP intake is complete.
- Do not mutate files under `acp-protocol/`.
- Use capability routing from `src/.acp/capability/capabilities.yaml`.
