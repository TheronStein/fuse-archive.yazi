-- ============================================================================
-- FUSE-ARCHIVE.YAZI - Enhanced Archive Mount Plugin
-- ============================================================================
--
-- Enhanced fork with comprehensive mount management, state tracking, and proper
-- async/sync architecture following Yazi's plugin model.
--
-- ARCHITECTURE OVERVIEW:
-- ----------------------
-- Yazi plugins run in ASYNC context by default. Complex operations (I/O,
-- iterations, processing) should happen in async. The sync context is ONLY
-- for accessing shared state and UI (cx).
--
-- ASYNC CONTEXT (default):
-- - All functions run here by default
-- - Can do: I/O operations, external processes, iterations, complex logic
-- - Cannot access: cx (current context), state directly
-- - Runs concurrently with main thread
--
-- SYNC CONTEXT (via ya.sync()):
-- - Accessed via ya.sync() blocks defined at TOP LEVEL
-- - Can access: cx, state
-- - MUST be simple: just get/set values, return immediately
-- - NO complex operations: no loops, no processing, no I/O
-- - Blocks the main thread, so keep it minimal
--
-- CORRECT PATTERN:
--   local get_state_snapshot = ya.sync(function(state)
--     return state  -- Just return, no processing
--   end)
--
--   local function process_data()  -- Async function
--     local snapshot = get_state_snapshot()
--     -- Do complex work here in async context
--     for k, v in pairs(snapshot) do
--       -- iterate, process, etc.
--     end
--   end
--
-- STATE STRUCTURE:
-- ----------------
-- state[archive_name] = {
--   tmp = "/path/to/mount/point",  -- Mount point path
--   cwd = "/original/directory",    -- Original directory before mount
-- }
-- state["global"] = {
--   fuse_dir = "/path/to/mount/dir",  -- Base mount directory
--   smart_enter = true/false,          -- Smart enter mode
-- }
--
-- AVAILABLE ACTIONS:
-- ------------------
-- mount    - Mount archive or smart enter (based on file type)
-- unmount  - Unmount archive and return to original location
-- list     - List all currently mounted archives
-- cleanup  - Clean up stale mount points
--
-- AUTHOR: Enhanced by TheronStein for comprehensive archive workflows
-- ORIGINAL: dawsers/fuse-archive.yazi
-- LICENSE: MIT
--
-- ============================================================================

-- ============================================================================
-- CONFIGURATION & CONSTANTS
-- ============================================================================

local shell = os.getenv("SHELL") or "/bin/sh"
local state_file = os.getenv("HOME") .. "/.core/.sys/cfg/yazi/plugins/.mount-state.json"

-- Supported archive extensions
local ARCHIVE_EXTENSIONS = {
  "zip", "gz", "bz2", "tar", "tgz", "tbz2", "txz", "xz", "tzs",
  "zst", "iso", "rar", "7z", "cpio", "lz", "lzma", "shar", "a",
  "ar", "apk", "jar", "xpi", "cab"
}

-- ============================================================================
-- UTILITY FUNCTIONS (Async Context)
-- ============================================================================

local function error(s, ...)
  ya.notify({
    title = "fuse-archive",
    content = string.format(s, ...),
    timeout = 5,
    level = "error"
  })
end

local function warn(s, ...)
  ya.notify({
    title = "fuse-archive",
    content = string.format(s, ...),
    timeout = 4,
    level = "warn"
  })
end

local function info(s, ...)
  ya.notify({
    title = "fuse-archive",
    content = string.format(s, ...),
    timeout = 3,
    level = "info"
  })
end

-- ============================================================================
-- SYNC BLOCKS - State Access Only (TOP LEVEL)
-- ============================================================================

-- Set state value for an archive/key
local set_state = ya.sync(function(state, archive, key, value)
  if not state[archive] then
    state[archive] = {}
  end
  state[archive][key] = value
end)

-- Get state value for an archive/key
local get_state = ya.sync(function(state, archive, key)
  if state[archive] then
    return state[archive][key]
  end
  return nil
end)

-- Get complete state snapshot (let async process it)
local get_all_state = ya.sync(function(state)
  local snapshot = {}
  for k, v in pairs(state) do
    if type(v) == "table" then
      snapshot[k] = {}
      for k2, v2 in pairs(v) do
        snapshot[k][k2] = v2
      end
    else
      snapshot[k] = v
    end
  end
  return snapshot
end)

-- Get current hovered file name
local current_file = ya.sync(function()
  local h = cx.active.current.hovered
  if h then
    return tostring(h.url), h.name, h.cha.is_dir
  end
  return nil, nil, false
end)

-- Get current directory path
local current_dir = ya.sync(function()
  return tostring(cx.active.current.cwd)
end)

-- Get current directory name only
local current_dir_name = ya.sync(function()
  return cx.active.current.cwd:name()
end)

-- Check if current directory is a mount point
local is_mount_point = ya.sync(function(state)
  local dir = cx.active.current.cwd:name()
  for archive, data in pairs(state) do
    if archive ~= "global" and data.tmp then
      -- Extract just the directory name from mount path
      local mount_name = data.tmp:match("([^/]+)$")
      if mount_name == dir then
        return true, archive
      end
    end
  end
  return false, nil
end)

-- Get hovered file info (name, is_dir, filename for extension check)
local get_file_info = ya.sync(function()
  local h = cx.active.current.hovered
  if not h then
    return nil, false, nil
  end
  return h.name, h.cha.is_dir, tostring(h.url)
end)

-- Check if smart_enter is enabled
local is_smart_enter = ya.sync(function(state)
  if state.global and state.global.smart_enter then
    return state.global.smart_enter
  end
  return false
end)

-- ============================================================================
-- ASYNC FUNCTIONS - Complex Operations
-- ============================================================================

-- Check if filename has an archive extension (async processing)
local function is_archive_file(filename)
  if not filename then
    return false
  end

  for _, ext in ipairs(ARCHIVE_EXTENSIONS) do
    if filename:match("%." .. ext .. "$") then
      return true
    end
  end

  return false
end

-- Get list of all mounts by processing state in async
local function get_all_mounts()
  local state_snapshot = get_all_state()
  local mounts = {}

  -- Process state snapshot in async context
  for archive, data in pairs(state_snapshot) do
    if archive ~= "global" and data.tmp then
      table.insert(mounts, {
        archive = archive,
        mount_point = data.tmp,
        cwd = data.cwd or "unknown",
        timestamp = os.time()  -- Current time as we don't track mount time
      })
    end
  end

  return mounts
end

-- Save mount registry to JSON file (async - file I/O)
local function save_registry()
  local mounts = get_all_mounts()
  local registry = {
    version = "1.0",
    timestamp = os.time(),
    mounts = mounts
  }

  -- Ensure directory exists
  local dir = state_file:match("(.*/)")
  os.execute("mkdir -p " .. ya.quote(dir))

  -- Write JSON
  local file = io.open(state_file, "w")
  if file then
    file:write("{\n")
    file:write('  "version": "' .. registry.version .. '",\n')
    file:write('  "timestamp": ' .. registry.timestamp .. ',\n')
    file:write('  "mounts": [\n')
    for i, mount in ipairs(mounts) do
      file:write('    {\n')
      file:write('      "archive": "' .. mount.archive:gsub('"', '\\"') .. '",\n')
      file:write('      "mount_point": "' .. mount.mount_point:gsub('"', '\\"') .. '",\n')
      file:write('      "cwd": "' .. mount.cwd:gsub('"', '\\"') .. '",\n')
      file:write('      "timestamp": ' .. mount.timestamp .. '\n')
      file:write('    }')
      if i < #mounts then
        file:write(',')
      end
      file:write('\n')
    end
    file:write('  ]\n')
    file:write('}\n')
    file:close()
  end
end

-- Clean up stale mount points (async - filesystem checks)
local function cleanup_stale_mounts()
  local mounts = get_all_mounts()
  local cleaned = 0

  for _, mount in ipairs(mounts) do
    -- Check if mount point still exists and is actually mounted
    local check = io.popen("mountpoint -q " .. ya.quote(mount.mount_point) .. " 2>/dev/null")
    local result = check:read("*a")
    local is_mounted = check:close()

    if not is_mounted then
      -- Stale mount point, clean it up
      os.execute("rmdir " .. ya.quote(mount.mount_point) .. " 2>/dev/null")
      -- Clear from state
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

-- ============================================================================
-- COMMAND EXECUTION (Async Context)
-- ============================================================================

local function run_command(cmd, args)
  local cwd = current_dir()
  local command = Command(cmd)

  for _, arg in ipairs(args) do
    command = command:arg(arg)
  end

  local child, cmd_err = command
    :cwd(cwd)
    :stdin(Command.INHERIT)
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :spawn()

  if not child then
    error("Spawn command failed with error code %s", cmd_err)
    return cmd_err
  end

  local output, out_err = child:wait_with_output()
  if not output then
    error("Cannot read command output, error code %s", out_err)
    return out_err
  elseif not output.status.success then
    error("Command exited with error code %s", output.status.code)
    return output.status.code
  end

  return 0
end

-- ============================================================================
-- MOUNT OPERATIONS (Async Context)
-- ============================================================================

-- Determine base mount directory from config
local function fuse_dir(opts)
  local state_dir
  if opts and opts.mount_dir then
    state_dir = opts.mount_dir
  else
    state_dir = os.getenv("XDG_STATE_HOME")
    if not state_dir then
      local home = os.getenv("HOME")
      if not home then
        state_dir = "/tmp"
      else
        state_dir = home .. "/.local/state"
      end
    end
  end
  return state_dir .. "/yazi/fuse-archive"
end

-- Generate unique temporary file name
local function get_tmp_file_name(path)
  local time_now = os.time()
  local hex_time = string.format("%x", time_now)
  return path .. ".tmp" .. hex_time
end

-- Create mount point directory
local function create_mount_path(file)
  local base_dir = get_state("global", "fuse_dir")
  if not base_dir then
    error("Mount directory not configured")
    return nil
  end

  local tmp_path = base_dir .. "/" .. file

  local ret_code = run_command("mkdir", { "-p", tmp_path })
  if ret_code ~= 0 then
    error("Cannot create mount point %s", tmp_path)
    return nil
  end

  return tmp_path
end

-- Mount an archive
local function do_mount(file)
  local filename, is_dir, full_path = get_file_info()

  if not filename then
    info("No file hovered")
    return
  end

  -- If it's a directory, just enter it
  if is_dir then
    ya.emit("enter", {})
    return
  end

  -- Check if it's an archive (in async context)
  local is_archive = is_archive_file(full_path)

  -- If it's not an archive, use smart_enter behavior
  if not is_archive then
    if is_smart_enter() then
      -- Smart enter: open the file
      ya.emit("open", {})
    else
      -- Regular enter
      ya.emit("enter", {})
    end
    return
  end

  -- It's an archive, proceed with mounting
  local tmp_file_name = get_tmp_file_name(file)
  local tmp_file_path = create_mount_path(tmp_file_name)
  if not tmp_file_path then
    return
  end

  -- Check if already mounted
  local existing_mount = get_state(tmp_file_name, "tmp")
  if existing_mount then
    warn("Archive already mounted at %s", existing_mount)
    ya.emit("cd", { existing_mount })
    return
  end

  info("Mounting %s...", file)

  local ret_code = run_command(shell, {
    "-c",
    "fuse-archive " .. ya.quote("./" .. file) .. " " .. ya.quote(tmp_file_path)
  })

  if ret_code ~= 0 then
    os.execute("rmdir " .. ya.quote(tmp_file_path) .. " 2>/dev/null")
    error("Unable to mount %s", file)
    return
  end

  -- Store mount state
  set_state(tmp_file_name, "cwd", current_dir())
  set_state(tmp_file_name, "tmp", tmp_file_path)

  -- Save registry
  save_registry()

  -- Navigate into mounted archive
  ya.emit("cd", { tmp_file_path })
  info("Mounted %s", file)
end

-- Unmount an archive
local function do_unmount()
  local is_mount, archive = is_mount_point()

  if not is_mount then
    -- Not a mount point, just leave directory
    ya.emit("leave", {})
    return
  end

  local tmp_file = get_state(archive, "tmp")
  if not tmp_file then
    warn("Mount point not found in state")
    ya.emit("leave", {})
    return
  end

  info("Unmounting %s...", archive)

  -- Navigate back to original location first
  local original_cwd = get_state(archive, "cwd")
  if original_cwd then
    ya.emit("cd", { original_cwd })
  else
    ya.emit("leave", {})
  end

  -- Give yazi time to navigate away
  -- Note: In Lua, we can't really sleep, but the cd should happen quickly

  -- Unmount using fusermount with fallbacks
  local unmount_cmd = "fusermount -u " .. ya.quote(tmp_file) .. " 2>/dev/null || " ..
                      "fusermount3 -u " .. ya.quote(tmp_file) .. " 2>/dev/null || " ..
                      "umount " .. ya.quote(tmp_file) .. " 2>/dev/null || true"

  os.execute(unmount_cmd)

  -- Clean up mount directory
  os.execute("rmdir " .. ya.quote(tmp_file) .. " 2>/dev/null || true")

  -- Clear state
  set_state(archive, "tmp", nil)
  set_state(archive, "cwd", nil)

  -- Save registry
  save_registry()

  info("Unmounted %s", archive)
end

-- List all currently mounted archives
local function do_list()
  local mounts = get_all_mounts()

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

-- ============================================================================
-- PLUGIN SETUP & ENTRY POINT
-- ============================================================================

local function setup(_, opts)
  local fuse = fuse_dir(opts)
  set_state("global", "fuse_dir", fuse)

  if opts and opts.smart_enter then
    set_state("global", "smart_enter", true)
  else
    set_state("global", "smart_enter", false)
  end

  -- Note: Auto-cleanup on startup disabled due to potential race conditions
  -- Users can manually run: :plugin fuse-archive --args=cleanup
end

return {
  entry = function(_, job)
    local args = job.args or {}
    local action = args[1]

    if not action then
      warn("No action specified")
      return
    end

    if action == "mount" then
      local _, file = current_file()
      if not file then
        info("No file hovered, entering directory...")
        ya.emit("enter", {})
        return
      end
      do_mount(file)

    elseif action == "unmount" then
      do_unmount()

    elseif action == "cleanup" then
      cleanup_stale_mounts()

    elseif action == "list" then
      do_list()

    else
      warn("Unknown action: %s", action)
    end
  end,

  setup = setup,
}
