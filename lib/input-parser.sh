#!/bin/bash
# Created: 2025-11-27
# Updated: 2026-01-04 02:40:00
# Library: input-parser.sh
#
# ============================================================================
# PURPOSE: Parse Claude hook input from env vars or stdin, extract content
# ============================================================================
#
# EXPORTS:
#   - parse_tool_input(): Parse tool input and set TOOL_NAME, CONTENT, FILE_PATH
#
# USAGE:
#   source "${HOOK_DIR}/lib/input-parser.sh"
#   parse_tool_input
#   echo "Tool: $TOOL_NAME, Content: $CONTENT, Path: $FILE_PATH"
#
# ============================================================================

parse_tool_input() {
    # Initialize defaults
    TOOL_NAME="${TOOL_NAME:-unknown}"
    TOOL_INPUT="${TOOL_INPUT:-}"
    CONTENT=""
    FILE_PATH=""

    # Method 1: Environment variables (preferred)
    if [ -n "${CLAUDE_TOOL_NAME:-}" ]; then
        TOOL_NAME="${CLAUDE_TOOL_NAME}"
        TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"
    else
        # Method 2: STDIN with timeout (check if available first)
        if [ -t 0 ]; then
            # Stdin is terminal (no data) - exit early
            return 0
        fi

        local raw_input
        raw_input=$(timeout 5s cat 2>/dev/null || echo "")

        # Sanitize invalid JSON escapes (e.g. \! from Claude Code)
        if [ -n "$raw_input" ]; then
            TOOL_INPUT=$(printf '%s\n' "$raw_input" | sed -E 's/\\([^"\\/bfnrtu])/\1/g')
        else
            TOOL_INPUT=""
        fi

        # Validate JSON
        if [ -z "$TOOL_INPUT" ] || ! printf '%s\n' "$TOOL_INPUT" | jq empty 2>/dev/null; then
            return 0
        fi

        # Extract tool name (try both .tool and .tool_name for compatibility)
        TOOL_NAME=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_name // .tool // "unknown"' 2>/dev/null || echo "unknown")
    fi

    # Extract content based on tool type
    # For env var mode: TOOL_INPUT contains direct params {"file_path":"...", "content":"..."}
    # For stdin mode: TOOL_INPUT contains {"tool_name":"...", "tool_input":{"file_path":"...", "content":"..."}}

    # Detect which mode by checking for tool_input key
    if printf '%s\n' "$TOOL_INPUT" | jq -e '.tool_input' >/dev/null 2>&1; then
        # STDIN mode - extract from .tool_input
        case "$TOOL_NAME" in
            Edit)
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null || echo "")
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
                ;;
            MultiEdit)
                # Concatenate all new_string values from edits array
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '[.tool_input.edits[].new_string // ""] | join("\n")' 2>/dev/null || echo "")
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
                ;;
            NotebookEdit)
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_input.new_source // ""' 2>/dev/null || echo "")
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_input.notebook_path // ""' 2>/dev/null || echo "")
                ;;
            Write|mcp__obsidian*)
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null || echo "")
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")
                ;;
            Bash)
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
                FILE_PATH=""
                ;;
            Read)
                CONTENT=""
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
                ;;
            *)
                CONTENT=""
                FILE_PATH=""
                ;;
        esac
    else
        # ENV VAR mode - extract directly
        case "$TOOL_NAME" in
            Edit)
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.new_string // ""' 2>/dev/null || echo "")
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // ""' 2>/dev/null || echo "")
                ;;
            MultiEdit)
                # Concatenate all new_string values from edits array
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '[.edits[].new_string // ""] | join("\n")' 2>/dev/null || echo "")
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // ""' 2>/dev/null || echo "")
                ;;
            NotebookEdit)
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.new_source // ""' 2>/dev/null || echo "")
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.notebook_path // ""' 2>/dev/null || echo "")
                ;;
            Write|mcp__obsidian*)
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.content // ""' 2>/dev/null || echo "")
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // .path // ""' 2>/dev/null || echo "")
                ;;
            Bash)
                CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // ""' 2>/dev/null || echo "")
                FILE_PATH=""
                ;;
            Read)
                CONTENT=""
                FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // ""' 2>/dev/null || echo "")
                ;;
            *)
                CONTENT=""
                FILE_PATH=""
                ;;
        esac
    fi

    # Export for hooks to use
    export TOOL_NAME TOOL_INPUT CONTENT FILE_PATH
}
