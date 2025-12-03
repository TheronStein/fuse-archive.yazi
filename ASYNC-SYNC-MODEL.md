# Yazi Plugin Async/Sync Architecture Reference

**CRITICAL UNDERSTANDING** - This document explains the Yazi plugin execution model that MUST be followed for plugins to work correctly.

## The Two Contexts

### ASYNC Context (Default)

**Where**: All plugin code runs here by default
**Runtime**: Tokio async runtime, concurrent with main thread
**Access**: Cannot access `cx` or `state` directly

**Can Do**:
- ✓ File I/O operations (`io.open`, `io.popen`)
- ✓ Execute external commands (`Command`, `os.execute`)
- ✓ Complex iterations and loops
- ✓ Data processing and transformations
- ✓ Network operations
- ✓ Heavy computations
- ✓ Call sync blocks to get data

**Cannot Do**:
- ✗ Access `cx` (current context)
- ✗ Access `state` directly
- ✗ Access UI elements

### SYNC Context (via ya.sync())

**Where**: Sync blocks defined with `ya.sync(function() ... end)`
**Runtime**: Main UI thread (blocks rendering)
**Access**: Has access to `cx` and `state`

**Can Do**:
- ✓ Read `cx.active.current.hovered`
- ✓ Read `cx.active.current.cwd`
- ✓ Read `state[key]`
- ✓ Write `state[key] = value`
- ✓ Return values to async context

**Cannot Do**:
- ✗ File I/O operations
- ✗ External commands
- ✗ Complex loops or iterations
- ✗ Heavy processing
- ✗ Anything that takes time

**MUST Be**:
- Defined at TOP LEVEL (not inside functions)
- MINIMAL (execute in microseconds)
- SIMPLE (just get/set, no logic)

## Pattern Examples

### ✓ CORRECT: Sync for Access, Async for Processing

```lua
-- Sync block: Just get state snapshot
local get_all_mounts = ya.sync(function(state)
  return state  -- Just return, no processing
end)

-- Async function: Process the data
local function list_mounts()
  local state_data = get_all_mounts()
  local mounts = {}

  -- Process in async context ✓
  for archive, data in pairs(state_data) do
    if archive ~= "global" and data.tmp then
      table.insert(mounts, {
        archive = archive,
        mount_point = data.tmp
      })
    end
  end

  return mounts
end
```

### ✓ CORRECT: Minimal Sync, Heavy Async

```lua
-- Sync: Just access cx
local get_current_file = ya.sync(function()
  local h = cx.active.current.hovered
  if h then
    return h.name, h.cha.is_dir
  end
  return nil, false
end)

-- Async: Do the work
local function process_file()
  local name, is_dir = get_current_file()

  if is_dir then
    ya.emit("enter", {})
  else
    -- Check file type, run commands, etc.
    local check = io.popen("file " .. ya.quote(name))
    local result = check:read("*a")
    check:close()

    -- Process result...
  end
end
```

### ✗ WRONG: Complex Work in Sync

```lua
-- ❌ BAD: Processing inside sync block
local list_mounts = ya.sync(function(state)
  local mounts = {}
  -- This loop blocks the UI thread!
  for archive, data in pairs(state) do
    if archive ~= "global" and data.tmp then
      table.insert(mounts, {
        archive = archive,
        mount_point = data.tmp
      })
    end
  end
  return mounts
end)
```

### ✗ WRONG: I/O in Sync

```lua
-- ❌ BAD: File I/O in sync block
local save_state = ya.sync(function(state)
  -- File I/O blocks the UI thread!
  local file = io.open("/tmp/state.json", "w")
  file:write(tostring(state))
  file:close()
end)
```

### ✗ WRONG: External Commands in Sync

```lua
-- ❌ BAD: External command in sync block
local check_mount = ya.sync(function()
  -- External process blocks UI thread!
  local result = io.popen("mountpoint -q /mnt/archive")
  return result:close()
end)
```

## Decision Tree: Sync or Async?

```
Do you need to access cx or state?
├─ NO  → Write as async function (default)
└─ YES → Do you need to do complex work with it?
    ├─ YES → Sync block to GET data, async function to PROCESS
    └─ NO  → Can use sync block (but keep it minimal!)
```

## Common Operations

| Operation | Context | Example |
|-----------|---------|---------|
| Get hovered file | Sync | `cx.active.current.hovered` |
| Get current directory | Sync | `cx.active.current.cwd` |
| Read state value | Sync | `return state[key]` |
| Write state value | Sync | `state[key] = value` |
| Iterate over state | **ASYNC** | Get snapshot in sync, iterate in async |
| File I/O | **ASYNC** | `io.open()`, `io.popen()` |
| External commands | **ASYNC** | `Command()`, `os.execute()` |
| Process data | **ASYNC** | Loops, transformations, calculations |
| Notifications | **ASYNC** | `ya.notify()` |
| Navigate | **ASYNC** | `ya.emit("cd", {})` |

## Sync Block Rules

1. **Define at TOP LEVEL** - Not inside other functions
2. **Keep MINIMAL** - Should execute in microseconds
3. **No LOOPS** - Unless trivial (< 10 iterations of simple ops)
4. **No I/O** - No file operations, no external commands
5. **No HEAVY PROCESSING** - Just get/set/return
6. **Return QUICKLY** - Main thread is blocked while running

## Anti-Patterns to Avoid

### 1. The "Do Everything in Sync" Anti-Pattern

```lua
-- ❌ WRONG
local do_mount = ya.sync(function(state)
  -- Getting file info: OK
  local h = cx.active.current.hovered
  if not h then return end

  -- Looping: BLOCKS UI
  for _, ext in ipairs(extensions) do
    if h.name:match(ext) then
      -- File I/O: BLOCKS UI
      local cmd = io.popen("fuse-archive " .. h.name)
      cmd:close()

      -- State update: OK
      state[h.name] = { mounted = true }
    end
  end
end)
```

**Fixed**:
```lua
-- ✓ CORRECT
local get_hovered = ya.sync(function()
  local h = cx.active.current.hovered
  return h and h.name or nil
end)

local function do_mount()
  local filename = get_hovered()
  if not filename then return end

  -- All heavy work in async
  for _, ext in ipairs(extensions) do
    if filename:match(ext) then
      local cmd = io.popen("fuse-archive " .. filename)
      cmd:close()

      set_state(filename, "mounted", true)
    end
  end
end
```

### 2. The "Nested Sync" Anti-Pattern

```lua
-- ❌ WRONG: Can't define sync blocks inside functions
local function my_function()
  local get_state = ya.sync(function(state)  -- ERROR!
    return state
  end)
end
```

**Fixed**:
```lua
-- ✓ CORRECT: Define at top level
local get_state = ya.sync(function(state)
  return state
end)

local function my_function()
  local state = get_state()  -- Use it here
end
```

### 3. The "Async Data Flow" Anti-Pattern

```lua
-- ❌ WRONG: Can't access cx in async function
local function get_filename()
  local h = cx.active.current.hovered  -- ERROR: cx not available
  return h and h.name or nil
end
```

**Fixed**:
```lua
-- ✓ CORRECT: Use sync block
local get_filename = ya.sync(function()
  local h = cx.active.current.hovered
  return h and h.name or nil
end)

local function process_file()
  local name = get_filename()  -- Get from sync, process in async
  -- ... do work with name ...
end
```

## Performance Implications

### Sync Block Performance

**Good** (< 1μs):
```lua
local get_value = ya.sync(function(state)
  return state.key  -- Instant
end)
```

**Acceptable** (< 100μs):
```lua
local get_snapshot = ya.sync(function(state)
  local snap = {}
  for k, v in pairs(state) do  -- Small iteration OK
    snap[k] = v
  end
  return snap
end)
```

**BAD** (> 1ms):
```lua
local process_all = ya.sync(function(state)
  -- Complex processing blocks UI!
  for archive, data in pairs(state) do
    for mount, info in pairs(data) do
      local result = io.popen("check " .. mount)  -- TERRIBLE!
      -- ...
    end
  end
end)
```

### Why This Matters

- Sync blocks run on UI thread
- UI freezes while sync block runs
- Even 10ms is noticeable lag
- 100ms+ causes visible stuttering
- File I/O can take seconds

## Testing Checklist

When writing/reviewing plugins:

- [ ] All `ya.sync()` blocks defined at TOP LEVEL
- [ ] No loops in sync blocks (or only trivial ones)
- [ ] No file I/O in sync blocks
- [ ] No external commands in sync blocks
- [ ] No heavy processing in sync blocks
- [ ] Sync blocks just get/set state or cx
- [ ] All complex work in async functions
- [ ] Proper data flow: sync GET → async PROCESS

## Summary

**Golden Rule**: Sync blocks are for **ACCESSING** shared state, not **PROCESSING** it.

**Data Flow**:
```
Sync Block (get data) → Async Function (process data) → Sync Block (set result)
```

**Remember**:
- Sync = Access only
- Async = Everything else
- Keep sync blocks MINIMAL
- Do ALL work in async

## References

- Yazi Plugin Documentation: https://yazi-rs.github.io/docs/plugins/overview
- This implementation: `/home/theron/.core/.proj/plugins/yazi/fuse-archive.yazi/main.lua`
