# hooks/

Optional Claude Code hooks that enforce iostesting usage.

## `iostesting-guard.sh`

A `PreToolUse` hook that intercepts Bash invocations and blocks the Apple CLI commands that iostesting replaces. When blocked, the model sees the suggested `iostesting` equivalent and tries again.

The skill is the carrot ("here's the right way"). The hook is the stick ("you can't do it the wrong way"). With both installed, a model can't drift back to raw `xcrun simctl boot` even if it forgot the skill guidance.

### What it blocks

- `xcodebuild test` (and variants like `test -only-testing:...`) → `iostesting test run`
- `xcrun simctl boot/shutdown/erase/create` → `iostesting sim ...`
- `xcrun simctl install/uninstall/launch/terminate` → `iostesting install/uninstall/launch/stop`
- `xcrun simctl io ... screenshot` → `iostesting screenshot`
- `xcrun simctl spawn ... log` → `iostesting logs`
- `xcrun simctl spawn ... xctest` → `iostesting test run`

### What it does NOT block

- `xcodebuild build` / `xcodebuild build-for-testing` / `xcodebuild test-without-building` — iostesting does not own building
- `xcodebuild -version` / `-list` / `-showsdks` / `-showBuildSettings` — informational
- `xcrun simctl list` — informational (matches `iostesting sim list` but not slower; not worth a guard)
- `xcrun simctl runtime ...` — out of scope for iostesting (may add in a future release)
- `xcrun notarytool` / `altool` / `actool` / etc. — different domain entirely
- `swift build` / `swift test` / `swift package` — also out of scope
- Commands that contain the tool names as arguments rather than commands (e.g. `echo xcodebuild`)

The hook handles `sudo`/`env`/`time`/`nohup`/`exec` wrappers, `bash -c "..."` indirection, and path-qualified invocations (`/usr/bin/xcodebuild`).

## Installing the hook

Add to `~/.claude/settings.json` (user-scope) so it applies to every project:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "command": "/absolute/path/to/iostesting/hooks/iostesting-guard.sh",
            "type": "command"
          }
        ],
        "matcher": "Bash"
      }
    ]
  }
}
```

Or scope it to one project by adding the same block to `.claude/settings.json` in that project's repo root.

After installing, restart Claude Code. The hook runs before every `Bash` tool call.

## Uninstalling

Remove the entry from `settings.json` and restart. The script file is harmless; you can delete or leave it.

## Why this design

Modeled on FlowDeck's pattern — a SKILL.md tells the model what to do, but a model can ignore advice. A `PreToolUse` hook with `matcher: "Bash"` runs `iostesting-guard.sh` against every shell command before execution. When the script exits 2, Claude Code shows the model the stderr message and refuses the call. The model reads the suggestion, retries with `iostesting`, succeeds.

Without the hook, the skill is a recommendation. With the hook, it's a contract.
