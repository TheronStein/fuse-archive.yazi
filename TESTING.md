# fuse-archive.yazi - Quick Testing Guide

**Status**: Ready for testing
**Date**: 2025-12-03

## Prerequisites

1. Yazi >= 0.3 installed
2. fuse-archive installed (`which fuse-archive`)
3. fusermount or fusermount3 installed
4. Plugin installed at `~/.config/yazi/plugins/fuse-archive.yazi/`

## Quick Setup

Add to `~/.config/yazi/init.lua`:

```lua
require("fuse-archive"):setup({
  smart_enter = true,  -- Recommended for testing
})
```

Add to `~/.config/yazi/keymap.toml`:

```toml
[manager]
prepend_keymap = [
  { on = ["<Right>"], run = "plugin fuse-archive --args=mount", desc = "Mount/Enter" },
  { on = ["<Left>"], run = "plugin fuse-archive --args=unmount", desc = "Unmount/Leave" },
  { on = ["a", "l"], run = "plugin fuse-archive --args=list", desc = "List mounts" },
  { on = ["a", "c"], run = "plugin fuse-archive --args=cleanup", desc = "Cleanup" },
]
```

## Test Scenarios

### Test 1: Basic Archive Mount ⭐ CRITICAL

**Purpose**: Verify archives can be mounted and entered

**Steps**:
1. Start Yazi: `yazi`
2. Navigate to a directory with archives (e.g., `~/Downloads/`)
3. Hover over a `.tar.gz` or `.zip` file
4. Press `<Right>` (or `:plugin fuse-archive --args=mount`)

**Expected**:
- Notification: "Mounting filename.tar.gz..."
- Notification: "Mounted filename.tar.gz"
- Yazi enters the archive (can see files inside)
- Location shows mount path

**Success Criteria**: ✓ Can browse archive contents

---

### Test 2: Archive Unmount ⭐ CRITICAL

**Purpose**: Verify archives can be properly unmounted

**Steps**:
1. While inside a mounted archive (from Test 1)
2. Press `<Left>` (or `:plugin fuse-archive --args=unmount`)

**Expected**:
- Notification: "Unmounting filename.tar.gz..."
- Notification: "Unmounted filename.tar.gz"
- Return to original directory
- Archive no longer mounted

**Verification**:
```bash
# From terminal
mount | grep fuse-archive
# Should show nothing
```

**Success Criteria**: ✓ Archive unmounted, back to original location

---

### Test 3: Smart Enter - Directory

**Purpose**: Verify directories are entered normally

**Steps**:
1. Hover over a directory (not an archive)
2. Press `<Right>`

**Expected**:
- Yazi enters the directory (normal behavior)
- No mounting attempt
- No notifications

**Success Criteria**: ✓ Normal directory navigation works

---

### Test 4: Smart Enter - Regular File

**Purpose**: Verify regular files are opened (not entered)

**Steps**:
1. Configure `smart_enter = true` in init.lua
2. Hover over a `.txt` or `.md` file (not archive)
3. Press `<Right>`

**Expected**:
- File opens in editor
- No mounting attempt

**Success Criteria**: ✓ Files open instead of trying to enter

---

### Test 5: Smart Enter - Archive File

**Purpose**: Verify archives still mount (not regular open)

**Steps**:
1. Configure `smart_enter = true` in init.lua
2. Hover over a `.tar.gz` file
3. Press `<Right>`

**Expected**:
- Archive mounts (not opened in editor)
- Can browse archive contents

**Success Criteria**: ✓ Archives mount even with smart_enter

---

### Test 6: List Mounts

**Purpose**: Verify mount tracking works

**Steps**:
1. Mount 2-3 different archives
2. Press `a` then `l` (or `:plugin fuse-archive --args=list`)

**Expected**:
- Notification: "Mounted archives: 3"
- Series of notifications showing each mount:
  ```
  archive1.tar.gz → /path/to/mount1
  archive2.zip → /path/to/mount2
  archive3.tar.gz → /path/to/mount3
  ```

**Success Criteria**: ✓ All mounts are tracked and listed

---

### Test 7: Double Mount Prevention

**Purpose**: Verify same archive can't be mounted twice

**Steps**:
1. Mount an archive (e.g., `test.tar.gz`)
2. Navigate out of the mount point
3. Try to mount the same `test.tar.gz` again

**Expected**:
- Warning: "Archive already mounted at /path/to/mount"
- Yazi navigates to existing mount point
- No duplicate mount created

**Success Criteria**: ✓ Prevents duplicate mounts

---

### Test 8: Cleanup Stale Mounts

**Purpose**: Verify cleanup removes stale mount directories

**Setup**:
```bash
# Create fake stale mount
mkdir -p ~/.local/state/yazi/fuse-archive/stale.tar.gz.tmp12345
```

**Steps**:
1. Press `a` then `c` (or `:plugin fuse-archive --args=cleanup`)

**Expected**:
- Notification: "Cleaned up 1 stale mount(s)"
- Stale directory removed

**Verification**:
```bash
ls ~/.local/state/yazi/fuse-archive/
# Should not show stale directory
```

**Success Criteria**: ✓ Stale mounts cleaned up

---

### Test 9: Registry Persistence

**Purpose**: Verify mount registry is saved

**Steps**:
1. Mount an archive
2. Check registry file:
   ```bash
   cat ~/.core/.sys/cfg/yazi/plugins/.mount-state.json
   ```

**Expected**:
```json
{
  "version": "1.0",
  "timestamp": 1234567890,
  "mounts": [
    {
      "archive": "test.tar.gz.tmp67a3f8",
      "mount_point": "/home/user/.local/state/yazi/fuse-archive/test.tar.gz.tmp67a3f8",
      "cwd": "/home/user/Downloads",
      "timestamp": 1234567890
    }
  ]
}
```

**Success Criteria**: ✓ Registry file exists and is valid JSON

---

### Test 10: Non-Archive Leave

**Purpose**: Verify normal leave works in non-mounted directories

**Steps**:
1. Navigate into a regular directory (not a mount)
2. Press `<Left>` (unmount key)

**Expected**:
- Yazi leaves directory normally (goes to parent)
- No unmount attempt
- No notifications

**Success Criteria**: ✓ Normal leave still works

---

## Debugging

### Check Yazi Logs

```bash
# Start yazi with debug logging
RUST_LOG=debug yazi

# Or check yazi logs
journalctl --user -u yazi
```

### Check Mount Status

```bash
# See what's mounted
mount | grep fuse-archive

# Or use mountpoint
mountpoint ~/.local/state/yazi/fuse-archive/*
```

### Check Plugin State

```bash
# View registry
cat ~/.core/.sys/cfg/yazi/plugins/.mount-state.json | jq .

# Check mount directories
ls -la ~/.local/state/yazi/fuse-archive/
```

### Manual Cleanup

If things get stuck:

```bash
# Unmount everything
fusermount -u ~/.local/state/yazi/fuse-archive/* 2>/dev/null
# or
fusermount3 -u ~/.local/state/yazi/fuse-archive/* 2>/dev/null

# Remove mount directories
rm -rf ~/.local/state/yazi/fuse-archive/*

# Clear registry
rm ~/.core/.sys/cfg/yazi/plugins/.mount-state.json
```

## Common Issues

### Issue: "fuse-archive: command not found"

**Solution**: Install fuse-archive
```bash
# Arch Linux
sudo pacman -S fuse-archive

# Ubuntu/Debian
sudo apt install fuse-archive

# From source
git clone https://github.com/google/fuse-archive
cd fuse-archive
make && sudo make install
```

### Issue: "fusermount: command not found"

**Solution**: Install FUSE
```bash
# Arch Linux
sudo pacman -S fuse3

# Ubuntu/Debian
sudo apt install fuse3
```

### Issue: Archive mounts but shows empty

**Cause**: fuse-archive may not support the archive format

**Solution**: Check supported formats
```bash
fuse-archive --help
```

### Issue: Can't unmount (device busy)

**Cause**: Yazi is still accessing files in the mount

**Solution**: Navigate out of mount first, then unmount

### Issue: Stale mounts accumulating

**Solution**: Run cleanup action
```
:plugin fuse-archive --args=cleanup
```

## Test Results Template

Copy and fill out after testing:

```
## Test Results - [Date]

### Environment
- OS:
- Yazi version:
- fuse-archive version:

### Test Results
- [ ] Test 1: Basic Archive Mount
- [ ] Test 2: Archive Unmount
- [ ] Test 3: Smart Enter - Directory
- [ ] Test 4: Smart Enter - Regular File
- [ ] Test 5: Smart Enter - Archive File
- [ ] Test 6: List Mounts
- [ ] Test 7: Double Mount Prevention
- [ ] Test 8: Cleanup Stale Mounts
- [ ] Test 9: Registry Persistence
- [ ] Test 10: Non-Archive Leave

### Issues Found
1. [Issue description]
   - Steps to reproduce:
   - Expected:
   - Actual:

### Notes
[Any additional observations]
```

## Performance Testing

For large archives or many mounts:

### Test: Large Archive Performance

**Setup**: Use archive with 1000+ files

**Steps**:
1. Mount large archive
2. Browse directories
3. Check responsiveness

**Expected**: No UI lag or freezing

### Test: Multiple Mounts

**Setup**: Mount 10+ archives

**Steps**:
1. Mount many archives
2. Run list action
3. Navigate between mounts
4. Unmount all

**Expected**: All operations remain fast

### Test: Rapid Mount/Unmount

**Steps**:
1. Rapidly mount and unmount same archive 10 times

**Expected**: No errors, no orphaned mounts

## Success Criteria

**Minimum for approval**:
- ✓ Tests 1-2 pass (basic mount/unmount)
- ✓ Tests 3-5 pass (smart_enter)
- ✓ Test 6 passes (list mounts)
- ✓ No errors in yazi logs

**Full approval**:
- ✓ All 10 tests pass
- ✓ No performance issues
- ✓ No errors or warnings
- ✓ Registry persists correctly

## Next Steps After Testing

1. **All tests pass**:
   - Commit changes
   - Update README if needed
   - Merge to master

2. **Some tests fail**:
   - Document failures
   - Fix issues
   - Re-test

3. **Performance issues**:
   - Profile bottlenecks
   - Optimize as needed
   - Re-test

## Contact

For issues or questions:
- Check IMPLEMENTATION.md for technical details
- Check ASYNC-SYNC-MODEL.md for architecture
- Check VERIFICATION.md for code quality

---

**Good luck with testing!** 🚀
