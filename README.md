# AgentShield

Runtime security for AI coding agents. Blocks prompt injection, scope creep, and accidental damage at the hook layer -- before the LLM can execute.

## The Problem

AI coding agents have shell access, file system access, and API credentials. They process external content (web pages, API responses, file contents) that may contain adversarial instructions. System prompt defenses are advisory -- the LLM can be convinced to ignore them.

AgentShield operates at the **hook layer**. Hooks run as separate OS processes. An `exit 2` from a PreToolUse hook is an absolute block -- the tool call never reaches the LLM. This is enforcement, not suggestion.

## Install

```bash
# Requires Bun (https://bun.sh)
bun /path/to/agentshield/bin/agentshield.ts init
```

Or after npm publish:
```bash
npx agentshield init
```

## 4 Defense Layers

**Layer 1 - Prompt Injection Scanner** (PostToolUse)
Scans output from WebFetch, WebSearch, Playwright, Lightpanda for 5 injection pattern families: instruction override, role hijacking, prompt extraction, data exfiltration, system file references.

**Layer 2 - Dangerous Command Blocker** (PreToolUse)
Blocks 20+ destructive patterns: docker prune, rm on system dirs, git force push to main, AI commit signatures, bulk docker operations, symlink creation.

**Layer 3 - Write Guard** (PreToolUse)
3-tier path protection (zeroAccess/readOnly/noDelete) with inline secret detection. Catches API keys, private keys, database URLs, JWTs in file content before they're written.

**Layer 4 - Security Monitor** (Agent)
Full BLOCK/ALLOW rule engine with 16 BLOCK conditions, 6 ALLOW exceptions, 9 evaluation rules across 3 threat vectors (prompt injection, scope creep, accidental damage).

## Architecture

```
Tool Call
  |
  v
PreToolUse Hooks (bash, exit 2 = hard block)
  |-- dangerous-command-blocker.sh  (Bash|Edit|Write)
  |-- write-guard.sh               (Edit|Write|NotebookEdit)
  |
  v
[Tool Executes]
  |
  v
PostToolUse Hooks (bash, warning injection)
  |-- prompt-injection-scanner.sh   (WebFetch|WebSearch|Playwright|Lightpanda)
```

## Commands

```bash
agentshield init        # Install hooks + agent + wire settings.json
agentshield status      # Show installed components and wiring
agentshield test        # Run 7 payloads against injection scanner
agentshield uninstall   # Clean removal of all components
```

## Customization

Edit `~/.agentshield/lib/damage-control-patterns.yaml` to add protected paths:

```yaml
zeroAccessPaths:
  - ~/.ssh/
  - ~/.gnupg/
readOnlyPaths:
  - /etc/hosts
noDeletePaths:
  - CLAUDE.md
  - LICENSE
```

## License

MIT
