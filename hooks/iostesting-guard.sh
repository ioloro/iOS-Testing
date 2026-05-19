#!/bin/bash
# iostesting-guard.sh — Claude Code PreToolUse hook
#
# Stops the model from reaching for `xcrun simctl` or `xcodebuild test` when
# the iostesting CLI already covers the same ground. Suggests the iostesting
# equivalent and exits non-zero so the Bash call is blocked.
#
# Scope (only blocked when the tool is the command being invoked, not an arg
# to another command like echo/grep/cat):
#   - xcodebuild test          → iostesting test run
#   - xcrun simctl boot        → iostesting sim boot
#   - xcrun simctl shutdown    → iostesting sim shutdown
#   - xcrun simctl erase       → iostesting sim erase
#   - xcrun simctl create      → iostesting sim create
#   - xcrun simctl install     → iostesting install
#   - xcrun simctl uninstall   → iostesting uninstall
#   - xcrun simctl launch      → iostesting launch
#   - xcrun simctl terminate   → iostesting stop
#   - xcrun simctl io ... screenshot  → iostesting screenshot
#   - xcrun simctl spawn ... log      → iostesting logs
#   - xcrun simctl spawn ... xctest   → iostesting test run
#
# Explicitly allowed (NOT blocked):
#   - xcodebuild build / build-for-testing / -version / -list / -showsdks /
#     -showBuildSettings / -showDestinations
#   - xcrun simctl list             (informational, no iostesting equivalent that's faster)
#   - xcrun simctl runtime ...      (out of scope for iostesting; may add later)
#   - xcrun notarytool / altool / actool / etc.
#   - swift build / swift test / swift package
#   - Commands that mention these tool names as arguments rather than commands.

set -e

INPUT=$(cat)

# Extract the command. Try Python, jq, then a regex fallback.
COMMAND=""
if [ -x /usr/bin/python3 ]; then
    COMMAND=$(
        IOSTESTING_GUARD_INPUT="$INPUT" /usr/bin/python3 -c 'import json, os
try:
    data = json.loads(os.environ.get("IOSTESTING_GUARD_INPUT", ""))
    cmd = data.get("tool_input", {}).get("command", "")
    if isinstance(cmd, str):
        print(cmd)
except Exception:
    pass' 2>/dev/null || true
    )
fi

if [ -z "$COMMAND" ] && command -v jq >/dev/null 2>&1; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
fi

if [ -z "$COMMAND" ]; then
    COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//')
fi

[ -z "$COMMAND" ] && exit 0

# Early exit: skip all checks if the command doesn't even mention the tools.
if ! echo "$COMMAND" | grep -qE 'xcodebuild|xcrun'; then
    exit 0
fi

# strip_prefixes: remove leading VAR=val, sudo/env/time/nice/nohup/exec wrappers,
# and bash -c "..." indirection so we match on the real first word.
strip_prefixes() {
    local seg="$1"
    local prev=""
    while [ "$seg" != "$prev" ]; do
        prev="$seg"
        while echo "$seg" | grep -qE '^[A-Za-z_][A-Za-z_0-9]*='; do
            local stripped
            stripped=$(echo "$seg" | sed -E 's/^[A-Za-z_][A-Za-z_0-9]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ ]*)[ ]*//')
            [ "$stripped" = "$seg" ] && break
            seg="$stripped"
        done
        if echo "$seg" | grep -qE '^(/[^ ]*/)?(sudo|env|time|command|nice|nohup|exec|eval)([ ]|$)'; then
            seg=$(echo "$seg" | sed -E 's/^[^ ]+[ ]+//')
        fi
        if echo "$seg" | grep -qE '^(/[^ ]*/)?(bash|sh|zsh)[ ]+(-[a-zA-Z]*)?c[ ]+'; then
            seg=$(echo "$seg" | sed -E "s/^[^ ]+([ ]+-[a-zA-Z]*)?[ ]+c[ ]+(['\"])//" | sed -E "s/['\"]\$//")
        fi
    done
    echo "$seg"
}

# segments_with_tool: split on ; && || | and yield segments that start with TOOL
segments_with_tool() {
    local tool="$1"
    echo "$COMMAND" | tr ';' '\n' | sed 's/&&/\n/g; s/||/\n/g; s/|/\n/g' | \
        sed 's/^[[:space:]]*//' | while IFS= read -r seg; do
            local effective
            effective=$(strip_prefixes "$seg")
            local normalized
            normalized=$(echo "$effective" | sed 's|^/[^ ]*/||')
            if echo "$normalized" | grep -qE "^${tool}([ ]|$)"; then
                echo "$normalized"
            fi
        done
}

block() {
    local blocked="$1"
    local suggestion="$2"
    echo "BLOCKED: $blocked" >&2
    echo "" >&2
    echo "Use the iostesting CLI instead:" >&2
    echo "  $suggestion" >&2
    echo "" >&2
    echo "iostesting is the runtime companion to the @ioloro/ios-testing skill." >&2
    echo "See 'iostesting --help' for the full surface." >&2
    exit 2
}

# ============================================================================
# xcodebuild test    →    iostesting test run
# (allow: build, build-for-testing, test-without-building, -version, -list, etc.)
# ============================================================================

XCBUILD_SEGS=$(segments_with_tool "xcodebuild")
if [ -n "$XCBUILD_SEGS" ]; then
    # Block: an xcodebuild invocation whose action word is `test`, including
    # `test -only-testing:...`, but NOT `build-for-testing` or `test-without-building`.
    if echo "$XCBUILD_SEGS" | grep -qE '([ ]|^)test([ ]|$)' && \
       ! echo "$XCBUILD_SEGS" | grep -qE 'build-for-testing|test-without-building'; then
        block "xcodebuild test" "iostesting test run -s <sim> <path-to-MyTests.xctest> [--filter Suite/test...]"
    fi
fi

# ============================================================================
# xcrun simctl <verb>   →   iostesting <verb>
# ============================================================================

SIMCTL_SEGS=$(segments_with_tool "xcrun" | grep -E '^xcrun[ ]+simctl[ ]' || true)
if [ -n "$SIMCTL_SEGS" ]; then
    case "$SIMCTL_SEGS" in
        *"simctl boot"*)
            block "xcrun simctl boot" "iostesting sim boot <name-or-udid>" ;;
        *"simctl shutdown"*)
            block "xcrun simctl shutdown" "iostesting sim shutdown <name-or-udid>" ;;
        *"simctl erase"*)
            block "xcrun simctl erase" "iostesting sim erase <name-or-udid>" ;;
        *"simctl create"*)
            block "xcrun simctl create" "iostesting sim create --name <n> --device-type <t> --runtime <r>" ;;
        *"simctl install"*)
            block "xcrun simctl install" "iostesting install -s <sim> <app-path>" ;;
        *"simctl uninstall"*)
            block "xcrun simctl uninstall" "iostesting uninstall -s <sim> <bundle-id>" ;;
        *"simctl launch"*)
            block "xcrun simctl launch" "iostesting launch -s <sim> <bundle-id>" ;;
        *"simctl terminate"*)
            block "xcrun simctl terminate" "iostesting stop -s <sim> <bundle-id>" ;;
    esac

    # Composite: simctl io ... screenshot   →   iostesting screenshot
    if echo "$SIMCTL_SEGS" | grep -qE 'simctl[ ]+io[ ].*screenshot'; then
        block "xcrun simctl io ... screenshot" "iostesting screenshot -s <sim> [-o ./shot.png]"
    fi

    # Composite: simctl spawn <udid> log ...   →   iostesting logs
    if echo "$SIMCTL_SEGS" | grep -qE 'simctl[ ]+spawn[ ]+[^ ]+[ ]+log([ ]|$)'; then
        block "xcrun simctl spawn ... log" "iostesting logs -s <sim> [--bundle-id <id>]"
    fi

    # Composite: simctl spawn <udid> xctest ...   →   iostesting test run
    if echo "$SIMCTL_SEGS" | grep -qE 'simctl[ ]+spawn[ ]+[^ ]+[ ]+xctest([ ]|$)'; then
        block "xcrun simctl spawn ... xctest" "iostesting test run -s <sim> <path-to-MyTests.xctest>"
    fi
fi

exit 0
