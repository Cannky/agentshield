#!/bin/bash
# Created: 2026-04-01
# PreToolUse: Merged write-protect + content-validator-slim
# 1. Block Edit/Write/MultiEdit on protected paths (zeroAccess + readOnly)
# 2. Detect secrets in content
# NOTE: Bypasses hook profiles (security-critical, always runs)
trap '' SIGPIPE
set +e

TOOL_NAME="${CLAUDE_TOOL_NAME:-}"
[[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "MultiEdit" && "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "NotebookEdit" ]] && exit 0

# Fast-path: plan files skip all validation
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"
[[ "$TOOL_INPUT" == *".claude/plans/"* ]] && exit 0

# Parse file_path and content_len separately (spaces in paths break single read)
FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // .path // ""' 2>/dev/null)
CONTENT_LEN=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.content // .new_string // "" | length' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

# Canonicalize to prevent path traversal bypass
FILE_PATH=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# ============================================================
# PART 1: PATH PROTECTION (from write-protect.sh)
# ============================================================
AGENTSHIELD_HOME="${AGENTSHIELD_HOME:-$HOME/.agentshield}"
PATTERNS_FILE="$AGENTSHIELD_HOME/lib/damage-control-patterns.yaml"
HOME_EXPANDED="${HOME:-/home/canky}"

if [[ -f "$PATTERNS_FILE" ]]; then
    # .example/.template/.sample files are convention-safe, skip zeroAccess blocking
    case "${FILE_PATH##*/}" in
        *.example|*.template|*.sample) ;; # skip path protection, fall through to secret scan
        *) check_zeroAccess=1 ;;
    esac

    check_path_match() {
        local file="$1" pattern="$2"
        pattern="${pattern/#\~/$HOME_EXPANDED}"
        case "$pattern" in
            */) [[ "$file" == "$pattern"* || "$file" == "${pattern%/}/"* ]] && return 0 ;;
            *\**) local base="${file##*/}" glob="${pattern##*/}"; [[ "$base" == $glob ]] && return 0 ;;
            *) local base="${file##*/}"; [[ "$base" == "$pattern" || "$file" == *"/$pattern" || "$file" == "$pattern" ]] && return 0 ;;
        esac
        return 1
    }

    check_section() {
        local section="$1" label="$2"
        if [[ "$section" != "zeroAccessPaths" ]]; then
            local base="${FILE_PATH##*/}"
            [[ "$base" == *.example || "$base" == *.template || "$base" == *.sample ]] && return
        fi
        while IFS= read -r pattern; do
            pattern=$(echo "$pattern" | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"')
            [[ -z "$pattern" || "$pattern" == "#"* ]] && continue
            if check_path_match "$FILE_PATH" "$pattern"; then
                cat <<ENDJSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: $FILE_PATH matches $label pattern '$pattern'."}}
ENDJSON
                exit 2
            fi
        done < <(sed -n "/^${section}:/,/^[a-zA-Z]/p" "$PATTERNS_FILE" | grep '^\s*-')
    }

    [[ -n "${check_zeroAccess:-}" ]] && check_section "zeroAccessPaths" "zero-access"
    check_section "readOnlyPaths" "read-only"
fi

# ============================================================
# PART 2: SECRET DETECTION (from content-validator-slim.sh)
# ============================================================
# Only check if there's actual content
[[ "$CONTENT_LEN" -eq 0 || "$CONTENT_LEN" == "null" ]] && exit 0

# Get content for scanning
CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.content // .new_string // empty' 2>/dev/null)
[[ -z "$CONTENT" ]] && exit 0

# Allowed files (skip secret detection)
case "$FILE_PATH" in
    *.env|*.env.local|*.env.example|*apis.env) exit 0 ;;
    "$HOME/.claude/hooks/"*.sh|"$HOME/.claude/hooks/lib/"*.sh) exit 0 ;;
esac

# Load shared secret patterns if available
if [[ -f "$AGENTSHIELD_HOME/lib/secret-patterns.sh" ]]; then
    source "$AGENTSHIELD_HOME/lib/secret-patterns.sh"
    if type contains_secret &>/dev/null; then
        if contains_secret "$CONTENT"; then
            echo "[WRITE-GUARD] BLOCKED: Secret/credential detected in $FILE_PATH" >&2
            exit 2
        fi
        exit 0
    fi
fi

# Fallback inline patterns
for pattern in \
    "ghp_[a-zA-Z0-9]{36}" "sk-[a-zA-Z0-9]{32,}" "sk-ant-[a-zA-Z0-9-]{40,}" \
    "AKIA[A-Z0-9]{16}" "AIza[a-zA-Z0-9_-]{35}" \
    "sk_live_[a-zA-Z0-9]{24,}" "pk_live_[a-zA-Z0-9]{24,}" \
    "eyJ[a-zA-Z0-9_-]{10,}\.eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}" \
    "xox[baprs]-[a-zA-Z0-9-]{10,}" \
    "-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"; do
    printf '%s\n' "$CONTENT" | grep -qE -- "$pattern" && {
        echo "[WRITE-GUARD] BLOCKED: Secret detected in $FILE_PATH" >&2
        exit 2
    }
done

# Database URLs with credentials
printf '%s\n' "$CONTENT" | grep -qE "(postgres|mysql|mongodb|redis)://[^:]+:[^@]+@" && {
    echo "[WRITE-GUARD] BLOCKED: Database URL with credentials in $FILE_PATH" >&2
    exit 2
}

exit 0
