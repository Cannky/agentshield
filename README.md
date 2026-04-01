# HookShield

> Runtime security for AI coding agents. Enforced at the OS process level — not advisory, not configurable away.

AI coding agents have shell access, filesystem access, and your API credentials. They process external content that may contain adversarial instructions. System prompts are advisory — the LLM can be convinced to ignore them. **HookShield is not.**

## Why Not Just a System Prompt?

| Approach | Mechanism | Can Be Overridden? |
|---|---|---|
| System prompt rule | "Don't run docker prune" | Yes — prompt injection, jailbreak, or confused deputy attack can bypass it |
| HookShield hook | `exit 2` from a bash process | No — the tool call is killed before the LLM sees the response |

A `PreToolUse` hook returning `exit 2` is an **absolute block**. The LLM never executes the tool call. There is no bypass, no social engineering path, no retry that gets through. It's OS-level enforcement.

## 5 Defense Layers

**Layer 1 — Prompt Injection Scanner** (PostToolUse)
Scans output from WebFetch, WebSearch, Playwright, and Lightpanda for 5 injection pattern families: instruction override, role hijacking, prompt extraction, data exfiltration, system file references. Fires _after_ the browser/fetch tool so poisoned web content is caught before the LLM acts on it.

**Layer 2 — Browser Injection Guard** (PostToolUse)
Dedicated scanner for Playwright and Lightpanda output. Detects direct agent instructions (`Claude, please run...`), social engineering patterns (`this page requires you to execute...`), and command injection attempts embedded in rendered page content.

**Layer 3 — Dangerous Command Blocker** (PreToolUse)
Blocks 20+ destructive patterns before they execute: `docker prune` (all forms), `rm` on system dirs, `git push --force` to main/master, AI attribution in commits, bulk docker operations via xargs/command substitution, symlink creation.

**Layer 4 — Write Guard** (PreToolUse)
3-tier path protection (`zeroAccessPaths` / `readOnlyPaths` / `noDeletePaths`) configured via YAML. Inline secret detection catches API keys, private keys, database URLs with credentials, JWTs, and Stripe keys before they're written to any file.

**Layer 5 — Security Monitor** (Agent)
Full BLOCK/ALLOW rule engine: 16 BLOCK conditions, 6 ALLOW exceptions, 9 evaluation rules across 3 threat vectors (prompt injection, scope creep, accidental damage). Runs as a Claude sub-agent with decision authority.

## 10/10 Tests Pass

```
$ bun hookshield/bin/hookshield.ts test

  [OK] Instruction override: BLOCK (expected BLOCK)
  [OK] Role hijacking: BLOCK (expected BLOCK)
  [OK] Prompt extraction: BLOCK (expected BLOCK)
  [OK] Data exfiltration: BLOCK (expected BLOCK)
  [OK] System file ref: BLOCK (expected BLOCK)
  [OK] Benign code review: PASS (expected PASS)
  [OK] Benign API docs: PASS (expected PASS)

  [OK] Direct agent instruction: BLOCK (expected BLOCK)
  [OK] Social engineering: BLOCK (expected BLOCK)
  [OK] Benign page content: PASS (expected PASS)

Results: 10/10 passed
```

## Quick Comparison: HookShield vs affaan-m/agentshield

| | HookShield | affaan-m/agentshield |
|---|---|---|
| Enforcement level | OS process (`exit 2` = hard block) | Config scanning |
| Can LLM override it? | No | Potentially |
| Prompt injection defense | Yes (Layer 1 + 2) | No |
| Write protection | Yes (Layer 4) | No |
| Browser content scanning | Yes (Layer 2) | No |
| Runtime | Bun + bash | Node |

HookShield operates at the OS process level. Each hook is a separate bash process that the Claude Code harness spawns. When a hook exits with code 2, the harness hard-kills the tool call — no LLM involvement, no override path.

## Install

```bash
# Requires Bun (https://bun.sh)
bun hookshield/bin/hookshield.ts init
```

Or after npm publish:
```bash
npx hookshield init
```

`init` copies all hooks to `~/.hookshield/`, wires them into `~/.claude/settings.json`, and installs the security monitor agent. One command, no manual JSON editing.

## Architecture

```
Tool Call
  |
  v
PreToolUse Hooks  (bash subprocess, exit 2 = hard block, LLM never sees response)
  |-- dangerous-command-blocker.sh  (Bash|Edit|Write)
  |-- write-guard.sh                (Edit|Write|NotebookEdit)
  |
  v (only if pre-hooks pass)
[Tool Executes]
  |
  v
PostToolUse Hooks  (bash subprocess, injects warning into LLM context)
  |-- prompt-injection-scanner.sh   (WebFetch|WebSearch|Playwright|Lightpanda)
  |-- browser-injection-guard.sh    (Playwright|Lightpanda|browser-use)
  |
  v
Agent: security-monitor  (BLOCK/ALLOW rule engine)
```

## Commands

```bash
hookshield init        # Install hooks + agent + wire settings.json
hookshield status      # Show installed components and wiring
hookshield test        # Run 10 payloads against injection scanner
hookshield uninstall   # Clean removal of all components
```

## Customization

Edit `~/.hookshield/lib/damage-control-patterns.yaml` to tune path protection:

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

Changes take effect immediately — hooks read this file on every invocation.

## License

MIT
