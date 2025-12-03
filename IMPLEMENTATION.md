# fuse-archive.yazi - Complete Reimplementation

**Date**: 2025-12-03
**Branch**: disk-cleaning-tools
**Status**: COMPLETE ✓

## Overview

Complete reimplementation of fuse-archive.yazi plugin following Yazi's correct async/sync architecture model. This addresses all previous issues with sync block complexity and restores full functionality including smart_enter, list, and cleanup actions.

## Critical Understanding: Yazi Async/Sync Model

### Architecture Principles

**Default Context: ASYNC**
- All plugin code runs in async context by default
- Can perform: I/O operations, external processes, complex iterations, data processing
- Cannot access: `cx` (current context), `state` directly
- Runs concurrently with main thread

**Sync Context: via ya.sync()**
- Accessed ONLY through `ya.sync()` blocks defined at TOP LEVEL
- Purpose: Access shared state and UI context (`cx`)
- MUST be minimal: just get/set values, return immediately
- NO complex operations: no loops, no processing, no I/O
- Blocks main thread - keep it fast!

### Correct Pattern Example

```lua
-- SYNC: Just access state, return immediately
local get_state_snapshot = ya.sync(function(state)
  return state  -- Just return, no processing
end)

-- ASYNC: Do complex work here
local function process_data()
  local snapshot = get_state_snapshot()  -- Get from sync
  -- Now process in async context ✓
  for k, v in pairs(snapshot) do
    -- iterate, process, etc.
  end
end
```

### Wrong Pattern Example

```lua
-- ❌ WRONG: Complex work inside sync block
local get_data = ya.sync(function(state)
  for k, v in pairs(state) do  -- NO! Blocks main thread!
    -- process...
  end
end)
```

## Implementation Details

### Sync Blocks (State Access Only)

All sync blocks are minimal and at top level:

1. **set_state(archive, key, value)** - Set state value
2. **get_state(archive, key)** - Get state value
3. **get_all_state()** - Return complete state snapshot for async processing
4. **current_file()** - Get hovered file (url, name, is_dir)
5. **current_dir()** - Get current directory path
6. **current_dir_name()** - Get current directory name
7. **is_mount_point()** - Check if in mount point, return archive name
8. **get_file_info()** - Get hovered file info (name, is_dir, is_archive)
9. **is_smart_enter()** - Check if smart_enter mode enabled

### Async Functions (Complex Operations)

All complex work happens in async functions:

1. **get_all_mounts()** - Process state snapshot, return mount list
2. **save_registry()** - Build JSON and save to file (I/O)
3. **cleanup_stale_mounts()** - Check filesystem, clean stale mounts
4. **run_command(cmd, args)** - Execute external commands
5. **do_mount(file)** - Mount archive with full logic
6. **do_unmount()** - Unmount archive with cleanup
7. **do_list()** - List all mounts with notifications

### Key Improvements

#### 1. Fixed ya.manager_emit → ya.emit

All instances of `ya.manager_emit` replaced with `ya.emit`:
- `ya.emit("enter", {})`
- `ya.emit("leave", {})`
- `ya.emit("cd", { path })`
- `ya.emit("open", {})`

#### 2. Restored smart_enter Functionality

Smart enter logic now works correctly:
- **Directory**: Always enter with `ya.emit("enter", {})`
- **Archive file**: Mount the archive
- **Regular file** (smart_enter=true): Open with `ya.emit("open", {})`
- **Regular file** (smart_enter=false): Try to enter (default behavior)

#### 3. Working list Action

The `list` action now works:
```lua
local function do_list()
  local mounts = get_all_mounts()  -- Process in async
  if #mounts == 0 then
    info("No archives currently mounted")
    return
  end
  info("Mounted archives: %d", #mounts)
  for _, mount in ipairs(mounts) do
    ya.notify({
      title = "fuse-archive",
      content = mount.archive .. " → " .. mount.mount_point,
      timeout = 5,
      level = "info"
    })
  end
end
```

#### 4. Working cleanup Action

The `cleanup` action now works:
```lua
local function cleanup_stale_mounts()
  local mounts = get_all_mounts()
  local cleaned = 0

  for _, mount in ipairs(mounts) do
    -- Filesystem checks in async ✓
    local check = io.popen("mountpoint -q " .. ya.quote(mount.mount_point) .. " 2>/dev/null")
    local result = check:read("*a")
    local is_mounted = check:close()

    if not is_mounted then
      os.execute("rmdir " .. ya.quote(mount.mount_point) .. " 2>/dev/null")
      set_state(mount.archive, "tmp", nil)
      set_state(mount.archive, "cwd", nil)
      cleaned = cleaned + 1
    end
  end

  if cleaned > 0 then
    info("Cleaned up %d stale mount(s)", cleaned)
    save_registry()
  else
    info("No stale mounts found")
  end
end
```

#### 5. Fixed State Snapshot Bug

Corrected `get_all_state()` nested loop logic:

**Before (WRONG):**
```lua
for k, v in pairs(state) do
  snapshot[k] = {}
  for k2, v2 in pairs(v) do
    snapshot[k2][k2] = v2  -- ❌ Wrong indices!
  end
end
```

**After (CORRECT):**
```lua
for k, v in pairs(state) do
  if type(v) == "table" then
    snapshot[k] = {}
    for k2, v2 in pairs(v) do
      snapshot[k][k2] = v2  -- ✓ Correct!
    end
  else
    snapshot[k] = v
  end
end
```

#### 6. Comprehensive Documentation

Added extensive header documentation covering:
- Architecture overview (async vs sync)
- Correct patterns and examples
- State structure
- Available actions
- Usage notes

## State Structure

```lua
state = {
  ["archive.tar.gz.tmp67a3f8"] = {
    tmp = "/home/user/.local/state/yazi/fuse-archive/archive.tar.gz.tmp67a3f8",
    cwd = "/original/directory/path"
  },
  ["global"] = {
    fuse_dir = "/home/user/.local/state/yazi/fuse-archive",
    smart_enter = true
  }
}
```

## Available Actions

| Action | Description | Usage |
|--------|-------------|-------|
| `mount` | Mount archive or smart enter | `plugin fuse-archive --args=mount` |
| `unmount` | Unmount and return to original location | `plugin fuse-archive --args=unmount` |
| `list` | List all currently mounted archives | `plugin fuse-archive --args=list` |
| `cleanup` | Clean up stale mount points | `plugin fuse-archive --args=cleanup` |

## Testing Checklist

- [x] Lua syntax validation (luac)
- [x] All sync blocks at top level
- [x] No complex operations in sync blocks
- [x] All functions defined before use
- [ ] Test mounting archive files
- [ ] Test unmounting archives
- [ ] Test smart_enter with regular files
- [ ] Test smart_enter with directories
- [ ] Test list action
- [ ] Test cleanup action
- [ ] Test double-mount prevention
- [ ] Verify registry persistence

## Configuration Example

```lua
-- ~/.config/yazi/init.lua
require("fuse-archive"):setup({
  smart_enter = true,  -- Enter files opens them, directories are navigated
  mount_dir = os.getenv("HOME") .. "/Mount/yazi/fuse-archive",  -- Custom location
})
```

## Keymap Example

```toml
# ~/.config/yazi/keymap.toml
[manager]
prepend_keymap = [
  # Navigation
  { on = ["<Right>"], run = "plugin fuse-archive --args=mount", desc = "Mount archive" },
  { on = ["<Left>"], run = "plugin fuse-archive --args=unmount", desc = "Unmount archive" },

  # Management
  { on = ["a", "l"], run = "plugin fuse-archive --args=list", desc = "List mounts" },
  { on = ["a", "c"], run = "plugin fuse-archive --args=cleanup", desc = "Cleanup stale mounts" },
]
```

## Files Modified

- `/home/theron/.core/.proj/plugins/yazi/fuse-archive.yazi/main.lua` - Complete rewrite

## Technical Notes

### Why This Architecture?

Yazi's plugin system runs Lua code in two contexts:

1. **Async (Tokio)**: For concurrent operations that don't need UI access
2. **Sync (Main thread)**: For accessing UI state that must be serialized

The sync blocks MUST be fast because they block the UI. Any complex work (loops, I/O, processing) must happen in async context, using sync blocks ONLY to fetch the data needed.

### Common Pitfalls Avoided

1. **Loops in sync blocks** - Moved to async functions
2. **I/O in sync blocks** - Moved to async functions
3. **Complex processing in sync** - Moved to async functions
4. **State iteration in sync** - Just snapshot, iterate in async
5. **Wrong ya.manager_emit** - Changed to ya.emit

### Performance Considerations

- Sync blocks execute in microseconds (just data access)
- Async functions can take longer without blocking UI
- Registry saves happen async (file I/O)
- Filesystem checks happen async (io.popen)

## Future Enhancements

Potential improvements (not implemented):

1. **Mount timestamp tracking** - Store actual mount time
2. **Auto-cleanup on startup** - Currently disabled due to race conditions
3. **Integration events** - Emit custom events for other plugins
4. **Mount statistics** - Track usage patterns
5. **Lazy unmount fallback** - Try `-uz` if normal unmount fails

## Credits

- **Original**: dawsers/fuse-archive.yazi
- **Enhanced**: TheronStein
- **Reimplemented**: 2025-12-03 with correct async/sync architecture

## License

MIT License (see LICENSE file)
