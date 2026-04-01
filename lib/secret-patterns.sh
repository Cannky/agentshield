# Created: 2026-03-10 05:00:00
# Library: secret-patterns.sh
#
# ============================================================================
# PURPOSE: Secret detection and redaction for hook pipelines
# ============================================================================
#
# EXPORTS:
#   - contains_secret(text): Returns 0 if secret found, 1 if clean
#   - redact_secrets(text): Returns text with secrets replaced by [REDACTED:type]
#   - redact_file(filepath): Redacts secrets in a file (for log processing)
#
# USAGE:
#   source "${HOOK_DIR}/lib/secret-patterns.sh"
#   if contains_secret "$my_text"; then echo "Secret found!"; fi
#   clean_text=$(redact_secrets "$my_text")
#
# ============================================================================

trap '' SIGPIPE
set +e

# Configuration
SECRET_LOG="${HOME}/.claude/state/secret-detections.log"
mkdir -p "$(dirname "$SECRET_LOG")" 2>/dev/null

# Internal: Log detection events
_secret_log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$SECRET_LOG" 2>/dev/null || true
}

# Pattern definitions: name|regex
# Each entry is "TYPE|EXTENDED_REGEX"
SECRET_PATTERNS=(
    "AWS_ACCESS_KEY|AKIA[0-9A-Z]{16}"
    "AWS_SECRET_KEY|aws_secret[_a-z]*[[:space:]]*[:=][[:space:]]*['\"]?[0-9a-zA-Z/+=]{40}"
    "GITHUB_TOKEN|gh[ps]_[A-Za-z0-9_]{36,}"
    "GITLAB_TOKEN|glpat-[A-Za-z0-9_-]{20,}"
    "HUGGINGFACE_TOKEN|hf_[a-zA-Z0-9]{30,}"
    "STRIPE_SECRET|sk_live_[A-Za-z0-9]{24,}"
    "STRIPE_PUBLISH|pk_live_[A-Za-z0-9]{24,}"
    "JWT_TOKEN|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
    "GENERIC_API_KEY|(api[_-]?key|apikey|secret[_-]?key|access[_-]?token)[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9_-]{20,}"
    "DATABASE_URL|(postgres|mysql|mongodb|redis)://[^:]+:[^@]+@"
    "SSH_PRIVATE_KEY|-----BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY-----"
    "DISCORD_TOKEN|[MN][A-Za-z0-9]{23,}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}"
    "SLACK_TOKEN|xox[bpras]-[A-Za-z0-9-]{10,}"
    "TELEGRAM_TOKEN|[0-9]{8,10}:[A-Za-z0-9_-]{35}"
    "OPENAI_KEY|sk-[A-Za-z0-9]{32,}"
    "ANTHROPIC_KEY|sk-ant-[A-Za-z0-9_-]{40,}"
    "GOOGLE_API_KEY|AIza[A-Za-z0-9_-]{35}"
    "SENDGRID_KEY|SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}"
    "TWILIO_KEY|SK[a-f0-9]{32}"
    "MAILGUN_KEY|key-[A-Za-z0-9]{32}"
    "NPM_TOKEN|npm_[A-Za-z0-9]{36}"
    "PYPI_TOKEN|pypi-[A-Za-z0-9_-]{50,}"
    "ETH_PRIVATE_KEY|0x[a-fA-F0-9]{64}"
    "DIGITALOCEAN|dop_v1_[a-f0-9]{64}"
    "VAULT_TOKEN|hvs\.[A-Za-z0-9_-]{24,}"
    "SUPABASE_KEY|sbp_[a-f0-9]{40}"
)

# Internal: Build combined regex from all patterns (cached)
_SECRET_COMBINED_REGEX=""
_build_combined_regex() {
    if [ -n "$_SECRET_COMBINED_REGEX" ]; then
        return
    fi
    local parts=()
    for entry in "${SECRET_PATTERNS[@]}"; do
        local regex="${entry#*|}"
        parts+=("$regex")
    done
    # Join with | for alternation
    local IFS='|'
    _SECRET_COMBINED_REGEX="${parts[*]}"
}

# Check if text contains any secret pattern
# Usage: contains_secret "$text"
# Returns: 0 if secret found, 1 if clean
contains_secret() {
    local text="$1"
    if [ -z "$text" ]; then
        return 1
    fi
    _build_combined_regex
    if echo "$text" | grep -qE "$_SECRET_COMBINED_REGEX" 2>/dev/null; then
        _secret_log "WARN" "Secret detected in input (length=${#text})"
        return 0
    fi
    return 1
}

# Redact secrets from text, replacing with [REDACTED:TYPE]
# Usage: clean=$(redact_secrets "$text")
redact_secrets() {
    local text="$1"
    if [ -z "$text" ]; then
        echo ""
        return
    fi
    local result="$text"
    local found=0
    for entry in "${SECRET_PATTERNS[@]}"; do
        local type="${entry%%|*}"
        local regex="${entry#*|}"
        local new_result
        # Use # as sed delimiter to avoid conflicts with | and / in patterns
        new_result=$(echo "$result" | sed -E "s#${regex}#[REDACTED:${type}]#g" 2>/dev/null)
        if [ -n "$new_result" ] && [ "$new_result" != "$result" ]; then
            found=1
            result="$new_result"
        fi
    done
    if [ "$found" -eq 1 ]; then
        _secret_log "INFO" "Secrets redacted from input"
    fi
    echo "$result"
}

# Redact secrets in a file (modifies in place using flock)
# Usage: redact_file "/path/to/logfile.log"
redact_file() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then
        _secret_log "WARN" "redact_file: file not found: ${filepath}"
        return 1
    fi
    local lockfile="${filepath}.lock"
    (
        flock -w 5 200 || { _secret_log "ERROR" "redact_file: lock timeout on ${filepath}"; return 1; }
        local content
        content=$(cat "$filepath" 2>/dev/null) || return 1
        local redacted
        redacted=$(redact_secrets "$content")
        if [ "$redacted" != "$content" ]; then
            local tmpfile="${filepath}.tmp.$$"
            echo "$redacted" > "$tmpfile" 2>/dev/null
            mv "$tmpfile" "$filepath" 2>/dev/null
            _secret_log "INFO" "File redacted: ${filepath}"
        fi
    ) 200>"$lockfile"
    rm -f "$lockfile" 2>/dev/null
}

# Export functions
export -f contains_secret
export -f redact_secrets
export -f redact_file
export -f _secret_log
export -f _build_combined_regex
