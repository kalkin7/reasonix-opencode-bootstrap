# Reasonix project memory

This file is loaded into every session's system prompt. It contains standing instructions for working with this project (Reasonix + OpenCode Go Bootstrap).

## Skill system integration

This project uses the agent-skills store for shared skills across CLI agents. The store is at `$env:USERPROFILE\agent-skills\` after running bootstrap-all.ps1.

### On-demand skill handling

Infrequent skills are kept in the synced global skill store and may not be active by default. When the user asks to add, load, or use an on-demand skill, handle it directly.

Preferred flow:
```
& "$env:USERPROFILE\agent-skills\use_project_skill.ps1" <query> -CLI reasonix -ProjectRoot (Get-Location).Path
```

- Use `-List` if the skill name is ambiguous.
- Do not manually edit `~\.agent-skills-active`; active folders are generated from profiles.

### Profile management
```
cd ~\agent-skills
.\setup_skills.ps1 Apply reasonix default
.\setup_skills.ps1 Verify
```

### Model configuration
- Auto/Ask (default): `deepseek-v4-flash` — fast, low-cost
- Plan (/plan): `deepseek-v4-pro` — strong reasoning
- Recovery (auto-retry): `deepseek-v4-pro` — review low-risk failures

### MCP Plugins
- `everything` — Windows file search via Everything (uvx everything-mcp)
- `upnote-lens` — UpNote note search/read/create (uvx upnote-lens-mcp)

### Sandbox
File writes are confined to the workspace root. The agent-skills store path must be registered in sandbox.allow_write (handled by bootstrap-all.ps1).
