# sbx-here: Open a Docker Sandbox here

Ensures existence of a [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) for the current workspace, handling initialization, attachment, and removal.
On first run, prompts for sandbox name and agent harness selection, persisting context in git config or `.sbx` file.
Subsequent runs attach to the existing sandbox. Supports `--remove` and `--recreate` flags for cleanup.
Designed for seamless integration with sbx CLI and flexible configuration management.

## Features:

- Context detection: Git repository vs standalone directory
- Persistent tracking via git config or `.sbx` file
- Interactive prompts for sandbox name and agent harness
- Config file management: Copies from `~/.config/sbx-here/$AGENT` to workspace root
- Hooks:
  - pre-run: Executes `.sbx-here/hooks/pre-run` before starting the sandbox
  - post-run: Executes `.sbx-here/hooks/post-run` after the sandbox exits
- Pass-through arguments to the underlying agent via `--`
- Inspection mode via `--name-only` to read state safely

## Non-Features:

- No multiple sandboxes per workspace
- No advanced configuration
- No error handling for sbx CLI failures (assumes sbx commands succeed)
- No validation of sandbox name uniqueness (relies on sbx CLI for errors)
- No support for non-interactive environments (requires user input on first run)
- No logging or debug output (only essential messages)
- No support for custom sbx CLI options (uses fixed options for create and run)
- No cleanup of copied config files on sandbox removal (assumes user manages workspace files)
- No support for multiple agents or dynamic agent selection after initial setup (agent is fixed on first run)
- No support for updating sandbox resources (cpus, memory) after creation (fixed on create)
- No support for sandbox status checks or conditional logic based on sandbox state (assumes user manages state)
