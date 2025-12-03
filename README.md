# fuse-archive.yazi (Enhanced)

**Enhanced fork** of [fuse-archive.yazi](https://github.com/dawsers/fuse-archive.yazi) with improved mount management, state tracking, and workflow integration.

Uses [fuse-archive](https://github.com/google/fuse-archive) to transparently mount and unmount archives in read-only mode, allowing you to navigate inside, view, and extract individual or groups of files.

## Enhancements Over Original

This fork adds comprehensive improvements for large-scale archive workflows:

### 🆕 Mount Registry & State Persistence
- **Persistent mount tracking** in `~/.core/.sys/cfg/yazi/plugins/.mount-state.json`
- Track all mounted archives with metadata (timestamp, original location)
- Survive yazi restarts with state recovery

### 🆕 Better Unmount Handling
- **Actually unmounts** archives using `fusermount`/`fusermount3`
- Fallback to lazy unmount (`-uz`) if normal unmount fails
- Proper cleanup of mount directories
- No more stale mounts!

### 🆕 Multi-Archive Awareness
- Prevent mounting the same archive twice
- List all currently mounted archives (`plugin fuse-archive --args=list`)
- Track mount count for status bar integration

### 🆕 Auto-Cleanup System
- Automatic cleanup of stale mounts on startup
- Manual cleanup command (`plugin fuse-archive --args=cleanup`)
- Detects and removes orphaned mount points

### 🆕 Integration Hooks
- Emits `mount_event` and `unmount_event` for plugin integration
- Works seamlessly with disk-ops.yazi for comprehensive disk management
- Enhanced notifications (info, warn, error levels)

### 🆕 Enhanced Actions
- `mount` - Mount archive (or enter if not archive)
- `unmount` - Properly unmount with cleanup
- `list` - Show all mounted archives
- `cleanup` - Clean up stale mounts

## Requirements

1. A relatively modern (>= 0.3) version of [yazi](https://github.com/sxyazi/yazi)
2. Linux system with [fuse-archive](https://github.com/google/fuse-archive) installed
3. `fusermount` or `fusermount3` (usually included with FUSE)

## Installation

### From GitHub (This Fork)

```sh
# Install from TheronStein's enhanced fork
ya pack -a TheronStein/fuse-archive
```

### Manual Installation

```sh
cd ~/.config/yazi/plugins/
git clone https://github.com/TheronStein/fuse-archive.yazi
```

## Configuration

Add to your `~/.config/yazi/init.lua`:

```lua
require("fuse-archive"):setup({
  smart_enter = true,                              -- Enter files opens them, directories are navigated
  mount_dir = os.getenv("HOME") .. "/Mount/yazi/fuse-archive",  -- Custom mount location
})
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `smart_enter` | boolean | `false` | If `true`, entering a file opens it, directories are navigated |
| `mount_dir` | string | `$XDG_STATE_HOME/yazi/fuse-archive` | Absolute path where archives are mounted |

**Default mount directory hierarchy:**
1. `$XDG_STATE_HOME/yazi/fuse-archive/...`
2. `$HOME/.local/state/yazi/fuse-archive/...`
3. `/tmp/yazi/fuse-archive/...`

## Usage

### Basic Navigation (Recommended)

Remap navigation keys to work transparently with archives:

```toml
# ~/.config/yazi/keymap.toml
[manager]
prepend_keymap = [
    { on = ["<Right>"], run = "plugin fuse-archive --args=mount", desc = "Enter or Mount archive" },
    { on = ["<Left>"], run = "plugin fuse-archive --args=unmount", desc = "Leave or Unmount archive" },
]
```

### Advanced Actions

```toml
[manager]
prepend_keymap = [
    # Navigation
    { on = ["<Right>"], run = "plugin fuse-archive --args=mount", desc = "Mount archive" },
    { on = ["<Left>"], run = "plugin fuse-archive --args=unmount", desc = "Unmount archive" },

    # Mount management
    { on = ["a", "l"], run = "plugin fuse-archive --args=list", desc = "List mounted archives" },
    { on = ["a", "c"], run = "plugin fuse-archive --args=cleanup", desc = "Clean stale mounts" },
]
```

### Command-Line Usage

From within yazi, you can also use:
- **List mounts**: `:plugin fuse-archive --args=list`
- **Cleanup**: `:plugin fuse-archive --args=cleanup`

## Supported Archive Types

`.zip`, `.gz`, `.bz2`, `.tar`, `.tgz`, `.tbz2`, `.txz`, `.xz`, `.tzs`, `.zst`, `.iso`, `.rar`, `.7z`, `.cpio`, `.lz`, `.lzma`, `.shar`, `.a`, `.ar`, `.apk`, `.jar`, `.xpi`, `.cab`

## Integration with Disk-Ops Plugin

This enhanced fork works seamlessly with [disk-ops.yazi](https://github.com/TheronStein/disk-ops.yazi) for comprehensive archive management:

- Mount state is shared across plugins
- Integration hooks notify disk-ops of mount events
- Combined workflows for archive deduplication and comparison

## Troubleshooting

### Stale Mounts

If archives don't unmount properly:

```sh
# From command line
fusermount -u ~/Mount/yazi/fuse-archive/*
# or
fusermount3 -u ~/Mount/yazi/fuse-archive/*

# Or in yazi, run cleanup
:plugin fuse-archive --args=cleanup
```

### Check Mount Status

```sh
# See what's mounted
mount | grep fuse-archive

# Or from yazi
:plugin fuse-archive --args=list
```

### Mount Registry

The plugin maintains a registry at:
```
~/.core/.sys/cfg/yazi/plugins/.mount-state.json
```

This JSON file tracks all mounts and is automatically updated on mount/unmount operations.

## Possible Conflicts

If `yazi.toml` has an opener that extracts archives, the UI may be confusing. Modify your `yazi.toml`:

```toml
# Remove or comment out the extract opener
extract = []
```

This ensures fuse-archive is the primary handler for archives.

## Workflow Integration

### Archive Deduplication Workflow

```bash
# 1. Mount multiple archives from yazi
# 2. Use archive-dedup functions to compare contents
archive-dedupe-cross ~/Mount/yazi/fuse-archive/*

# 3. Clean up when done
:plugin fuse-archive --args=cleanup
```

### Remote Repository Comparison

```bash
# 1. Mount local archives in yazi
# 2. Mount remote via rclone
# 3. Compare using archive-compare-remote
```

## Credits

- **Original Author**: [dawsers](https://github.com/dawsers) - Original fuse-archive.yazi plugin
- **Enhanced By**: TheronStein - Mount management, state tracking, integration hooks
- **Based On**: [archivemount.yazi](https://github.com/AnirudhG07/archivemount.yazi)
- **Uses**: [fuse-archive](https://github.com/google/fuse-archive) by Google

## License

MIT License (see LICENSE file)

## Changelog

### Enhanced Fork v1.0 (2025-12-03)
- ✨ Added mount registry with JSON state persistence
- ✨ Implemented proper unmount with fusermount support
- ✨ Added auto-cleanup of stale mounts on startup
- ✨ Added `list` and `cleanup` actions
- ✨ Integration hooks for disk-ops.yazi
- ✨ Multi-archive awareness (prevent double mounts)
- ✨ Enhanced notifications (info/warn/error levels)
- 🐛 Fixed unmount not actually unmounting (was just calling leave)
- 🐛 Fixed Command args handling for better reliability
- 📚 Comprehensive documentation with workflow examples
