# 00-python: module API and tests

`lib.sh` is sourced by the other modules' install scripts:

```sh
. modules/00-python/lib.sh
kit_uv_tool_install <pkgdir>     # installs the CLI from kit/offline/wheels
kit_backup <file> [module]       # moves the file to ~/.local/share/work-kit/backups/<module>/
kit_uv <args>                    # runs uv, then clears the world-writable .lock files it leaves
kit_fix_lock_perms               # the same on its own
```

Tests: `bash tests/test-lib.sh` in the module folder.
