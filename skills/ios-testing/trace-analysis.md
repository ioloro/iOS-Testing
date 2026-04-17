# Xcode Instruments Trace (.trace) File Analysis Reference

Read and analyze `.trace` files using the `xctrace` CLI tool to diagnose performance issues without requiring the user to open Instruments.

## Reading Traces with xctrace

### Step 1: Export the Table of Contents

```bash
xctrace export --input /path/to/file.trace --toc
```

From the TOC, identify the app (process name/PID), device/OS, and available schemas.

### Step 2: Identify Available Schemas

Common schemas by template:

| Template | Key Schemas |
|----------|-------------|
| **Time Profiler** | `time-profile` (symbolicated), `time-sample` (raw), `potential-hangs` |
| **CPU Profiler** | `time-sample`, `gcd-perf-event` |
| **CPU Counters** | `kdebug-counters-with-time-sample`, `CounterMetricByThread`, `CounterMetricByCore` |
| **System Trace** | `context-switch`, `syscall`, `thread-narrative`, `virtual-memory`, `thread-info` |
| **Allocations** | Uses `tracks/track` XPath (see Memory section) |
| **SwiftUI** | `os-signpost-arg`, `time-sample` |
| **Swift Concurrency** | `os-signpost-arg`, `time-sample` |
| **Animation Hitches** | `os-signpost-arg`, hitch-related tables |
| **App Launch** | `time-sample`, `os-signpost-arg` |
| **Logging** | `os-log-arg` |

### Step 3: Export Table Data

```bash
# Standard schema export (CPU, scheduling, signposts):
xctrace export --input file.trace \
  --xpath '/trace-toc/run/data/table[@schema="SCHEMA_NAME"]'

# Memory instruments use tracks path:
xctrace export --input file.trace \
  --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]'
```

Replace `SCHEMA_NAME` with: `time-profile`, `potential-hangs`, `syscall`, `context-switch`, `thread-narrative`, `virtual-memory`, `os-signpost-arg`, `os-log-arg`, `thread-info`, `dyld-library-load`.

### Important: `time-sample` vs `time-profile`

- **`time-profile`** — **Use this one.** Symbolicated backtraces with `<frame name="...">`.
- **`time-sample`** — Raw `kperf-bt` hex addresses, not symbolicated. Avoid.

## Understanding the XML Output

### Row Data and the id/ref System (Critical)

Every element uses deduplication: first occurrence has `id="N"`, subsequent use `ref="N"`. Build lookup dicts to resolve.

```xml
<row>
  <thread id="77" fmt="Main Thread (0x29c3f2)">
    <process id="78" fmt="MyApp (98211)" pid="98211"/>
  </thread>
  <thread-state id="8" fmt="Running"/>
</row>
<row>
  <thread ref="77"/>       <!-- same Main Thread -->
  <thread-state ref="8"/>  <!-- same Running state -->
</row>
```

Key patterns:
- **`id`/`ref`**: Build dict mapping id→element for threads, states, frames. Check `id` first, then `ref`.
- **`fmt`**: Human-readable value for display/matching.
- **`<sentinel/>`**: Null/missing value.
- **Thread identification**: Main thread `fmt` contains "Main Thread". ID varies per trace.
- **Thread states**: "Running" (CPU-bound), "Runnable" (preempted), "Blocked" (I/O/lock).

### Backtrace Frames (time-profile only)

```xml
<backtrace id="14">
  <frame name="MyApp.overlappingTargets(for:in:)" addr="0x10194b9b8">
    <binary name="MyApp" UUID="..." path="..."/>
  </frame>
</backtrace>
```

**Warning**: `time-sample` has `<kperf-bt>` with raw addresses, NOT `<frame>` elements.

### Duration/Weight Values

Nanoseconds (raw) with `fmt` for display: `<weight id="42" fmt="1.00 ms">1000000</weight>`

## Analysis Workflow

### 1. Discover → 2. Export → 3. Analyze → 4. Fix

**What to look for by data type:**

| Data | Issues |
|------|--------|
| **time-profile** | Hot call stacks, main thread CPU-bound work |
| **potential-hangs** | Hang duration/severity, time ranges |
| **context-switch** | Preemptions, lock contention, priority inversions |
| **syscall** | High wait time (I/O bound), tight loops |
| **virtual-memory** | Page faults, memory pressure |
| **os-signpost-arg** | Long signpost intervals, slow SwiftUI body evals |

## Hang Analysis Workflow

### Step 1: Export hang events

```bash
xctrace export --input file.trace \
  --xpath '/trace-toc/run/data/table[@schema="potential-hangs"]' | head -200
```

Note worst hang's start/end times.

### Step 2: Export time-profile to file

```bash
xctrace export --input file.trace \
  --xpath '/trace-toc/run/data/table[@schema="time-profile"]' \
  --output /tmp/time_profile.xml
```

### Step 3: Parse with Python

The ref/id system makes grep unreliable. Use `xml.etree.ElementTree`:

```python
import xml.etree.ElementTree as ET
from collections import Counter

tree = ET.parse('/tmp/time_profile.xml')
root = tree.getroot()
node = root.find('.//node')

# Find main thread and Running state ref ids
main_thread_ref = None
running_state_ref = None
for row in node.findall('row'):
    thread = row.find('thread')
    if thread is not None and thread.get('id') and 'Main Thread' in thread.get('fmt', ''):
        main_thread_ref = thread.get('id')
    state = row.find('thread-state')
    if state is not None and state.get('id') and 'Running' in state.get('fmt', ''):
        running_state_ref = state.get('id')
    if main_thread_ref and running_state_ref:
        break

# Build frame name lookup (id -> name)
frame_names = {}
for row in node.findall('row'):
    bt = row.find('backtrace')
    if bt is None: continue
    for frame in bt.findall('frame'):
        fid, fname = frame.get('id'), frame.get('name', '')
        if fid and fname: frame_names[fid] = fname

# Count frames on main thread in Running state
inclusive, leaf = Counter(), Counter()
total = 0
for row in node.findall('row'):
    thread, state = row.find('thread'), row.find('thread-state')
    if thread is None or state is None: continue
    tid = thread.get('id', thread.get('ref', ''))
    sid = state.get('id', state.get('ref', ''))
    if tid != main_thread_ref or sid != running_state_ref: continue

    bt = row.find('backtrace')
    if bt is None: continue
    total += 1
    frames = []
    for frame in bt.findall('frame'):
        fid = frame.get('id', frame.get('ref', ''))
        name = frame.get('name', '') or frame_names.get(fid, f'ref:{fid}')
        if fid and name: frame_names[fid] = name
        frames.append(name)
    for name in set(frames): inclusive[name] += 1
    if frames: leaf[frames[0]] += 1

print(f"Main thread Running samples: {total}")
print("\n=== TOP INCLUSIVE ===")
for name, count in inclusive.most_common(20): print(f"  {count:6d}  {name}")
print("\n=== TOP LEAF ===")
for name, count in leaf.most_common(20): print(f"  {count:6d}  {name}")
```

### Key: Filter by Thread AND State

- **Main thread** only (hangs are main-thread freezes)
- **Running** state only (CPU-bound work, not I/O waits)
- Both **inclusive** (function + callees) and **leaf** (where CPU spins)

## Hang Severity Categories

| Duration | Category | Impact |
|----------|----------|--------|
| < 100ms | Imperceptible | Feels instant |
| 100–250ms | Micro hang | Subconsciously noticeable |
| 250–500ms | Hang | Clearly noticeable |
| > 500ms | Severe hang | App feels frozen |

## Recording Traces from CLI

```bash
# Attach to running app (most common)
xcrun xctrace record --template 'Time Profiler' --time-limit 30s \
  --output /tmp/App.trace --attach 'AppName'

# Launch and profile (use full binary path to avoid LaunchServices mismatch)
xcrun xctrace record --template 'Time Profiler' --time-limit 10s \
  --launch -- /path/to/App.app/Contents/MacOS/App

# Compose instruments (add Hangs detection to any trace)
xcrun xctrace record --instrument 'Time Profiler' --instrument 'Hangs' \
  --time-limit 30s --attach 'AppName'

# Ring buffer (keeps last N seconds — reproduce bug, then stop)
xcrun xctrace record --template 'Time Profiler' --window 10s --attach 'AppName'

# iOS device
xcrun xctrace record --template 'Time Profiler' --device 'iPhone' \
  --time-limit 30s --attach 'AppName'
```

Key options: `--template <name>`, `--instrument <name>` (repeatable), `--time-limit <duration>`, `--window <duration>` (ring buffer), `--attach <pid|name>`, `--launch -- <cmd>`, `--device <name|UDID>`, `--append-run` (A/B comparison), `--no-prompt` (CI).

### Symbolicate a trace

```bash
xcrun xctrace symbolicate --input trace.trace --dsym /path/to/App.dSYM
```

### List resources

```bash
xcrun xctrace list templates    # Recording templates
xcrun xctrace list instruments  # Individual instruments
xcrun xctrace list devices      # Connected devices/simulators
```

## Suggesting the Right Trace

| User's Problem | Template | Notes |
|---------------|----------|-------|
| App hangs/freezes | **Time Profiler** | CPU stacks + hang detection. Best general-purpose starting point. |
| High CPU (100%) | **CPU Profiler** | Samples on CPU clock (won't alias periodic work like Time Profiler) |
| High/growing memory | **Allocations** | Object counts, growth, allocation stacks |
| Memory leaks | **Leaks** | Unreferenced memory detection |
| Scroll jank | **Animation Hitches** | Frame delivery, hitch severity |
| Slow launch | **App Launch** | Pre-main/post-main phases |
| Excessive SwiftUI updates | **SwiftUI** | Body eval times, Cause & Effect graph (Xcode 26+) |
| Thread contention | **System Trace** | Context switches, lock contention, priority inversions |
| Async/actor issues | **Swift Concurrency** | Task scheduling, actor contention |
| Battery drain | **Power Profiler** | Energy impact by subsystem |
| Core ML slow | **Core ML** | Inference time, compute unit selection |
| Disk I/O | **File Activity** | File reads/writes, latency |
| GPU bottleneck | **Metal System Trace** | GPU scheduling, shader execution |

**When unsure, start with Time Profiler** — it gives enough signal to narrow down CPU vs I/O vs contention.

**Processor Trace** (M4+/A18+ only): records every instruction (~1% overhead). Massive data — limit to seconds.

## SwiftUI Instrument (Xcode 26+)

Four tracking lanes: **Update Groups**, **Long View Body Updates**, **Long Representable Updates**, **Other Long Updates**. Color-coded orange/red by severity.

**Cause & Effect graph**: visualizes user interaction → state change → which views re-evaluated. Essential for finding unnecessary view updates.

## Tips and Gotchas

**Export:**
- `--filter-time` does NOT exist — export full data, filter with Python
- Use `time-profile` not `time-sample` for symbolicated stacks
- Always `--output /tmp/file.xml` for large traces — piping loses ref context
- Ref resolution is mandatory — build id→name lookup dicts
- CPU schemas: `data/table[@schema="..."]`. Memory schemas: `tracks/track[@name="..."]/details/detail[...]`
- Multiple runs: `/trace-toc/run[@number="1"]/...`
- Missing symbols: `xcrun xctrace symbolicate --dsym path`

**Recording:**
- Wrong app: use full binary path with `--launch`
- Empty trace: use `--attach` for GUI apps, increase `--time-limit`
- Simulator: Duration metric only — physical device for CPU/hitch data
- Xcode 26: if template export fails, re-record with `--instrument` flags
