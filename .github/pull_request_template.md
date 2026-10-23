## What this changes

<!-- One or two lines. Link the issue it fixes, for example: Fixes #123 -->

## Checklist

- [ ] Still read-only: writes nothing except a report someone asks to save
- [ ] Never prints, stores or sends a key
- [ ] Runs nothing it finds, and adds no dependencies
- [ ] Works on bash 3.2 (`/bin/bash` on macOS)
- [ ] `bash tests/run.sh` and shellcheck pass
- [ ] If `gird-check.ps1` changed: `bash tests/run-ps.sh` passes, and it still runs on Windows PowerShell 5.1
- [ ] TELEMETRY.md is updated if the shared counts changed
- [ ] Commits are signed off (`git commit -s`)
