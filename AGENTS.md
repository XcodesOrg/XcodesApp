# Releasing Xcodes.app

Use the local release command from this repository on the maintainer’s Mac.

| Task | Command |
| --- | --- |
| Preview a release | `./Scripts/release 4.2.1 --dry-run` |
| Publish a stable release | `./Scripts/release 4.2.1` |
| Publish a prerelease | `./Scripts/release 4.2.1 --prerelease` |
| Continue an interrupted release | `./Scripts/release --resume v4.2.1b43` |

Use `--dry-run` for planning and release verification. Run a publishing command only when the user explicitly requests publication of the named version or resumption of a named tag. Use the actual version and the tag printed by the command.

The command builds from GitHub `main`. It manages the app version, signed tag, GitHub release, and both Sparkle feeds. If it stops after saving an archive, continue with the printed `--resume` command. See the [release runbook](README.md#releasing-a-new-version) for credential setup, release notes, and recovery.
