#!/usr/bin/env bash
set -euo pipefail

VERSION="0.2"
SBX_FILE=".sbx"
SBX_NAME=""
AGENT=""
WORKSPACE=""
CREATE=false
REMOVE=false
CLEANUP_ONLY=false
NAME_ONLY=false
AGENT_ARGS=()

usage() {
    local cmd=$(basename "$0")
    cat << EOF
Usage: $cmd [OPTIONS] [-- AGENT_ARGS...]

Manage a Docker sandbox for the current workspace.

OPTIONS:
  --help, -h, -?         Show this help message
  --version              Show version information
  --remove               Remove the sandbox and clean up configurations
  --recreate             Remove and recreate the sandbox
  --name-only            Print the configured sandbox name and exit immediately

DESCRIPTION:
  Initializes or connects to a Docker sandbox. On first run, prompts for
  sandbox name and harness selection. Subsequent runs attach to the existing
  sandbox. Any arguments past '--' are passed cleanly into the sandbox agent runtime.

EXAMPLES:
  $cmd                # Start or attach to sandbox
  $cmd --name-only    # Get the name without triggering side-effects
  $cmd --remove       # Remove sandbox and configurations
  $cmd --recreate     # Destroy and recreate sandbox
  $cmd --help         # Show this message
  $cmd -- --verbose   # Pass '--verbose' directly to your agent

EOF
}

# Parse CLI flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help | -h | -?)
            usage
            exit 0
            ;;
        --version)
            echo "sbx-here v$VERSION"
            exit 0
            ;;
        --remove)
            REMOVE=true
            CLEANUP_ONLY=true
            shift
            ;;
        --recreate)
            CREATE=true
            REMOVE=true
            shift
            ;;
        --name-only)
            NAME_ONLY=true
            shift
            ;;
        --)
            shift
            AGENT_ARGS=("$@")
            break
            ;;
        *)
            echo "Unknown flag: $1" >&2
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Environment detection & state extraction
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IN_GIT=true
    SBX_NAME=$(git config --local sbx.name 2>/dev/null || true)
    AGENT=$(git config --local sbx.agent 2>/dev/null || true)
    WORKSPACE=$(git rev-parse --show-toplevel)
else
    IN_GIT=false
    WORKSPACE="$PWD"
    if [[ -f "$SBX_FILE" ]]; then
        SBX_NAME=$(tr -d '\r\n' < "$SBX_FILE" | xargs)
    fi
fi

# Prompt user to select an agent harness
select_harness() {
    PS3="Enter choice (1-3): "
    options=("claude" "copilot" "opencode")
    select agent in "${options[@]}"; do
        if [[ -n "$agent" ]]; then
            echo "$agent"
            return 0
        fi
        echo "Invalid selection. Pick a valid harness."
    done
    PS3=""
}

# Clean up sbx configurations (git config or .sbx file)
cleanup_config() {
    if [[ "$IN_GIT" == true ]]; then
        git config --local --remove-section sbx 2>/dev/null || true
    else
        if [[ -f "$SBX_FILE" ]]; then
            rm -f "$SBX_FILE"
        fi
    fi
}

# Create the docker sandbox
create_sandbox() {
    sbx create --cpus 4 --memory 4g --name "$@"
}

# Copy config files from ~/.config/sbx-here/$AGENT to workspace root
copy_config_files() {
    if [[ -z "$AGENT" ]]; then
        return
    fi

    local config_dir="$HOME/.config/sbx-here/$AGENT"
    if [[ ! -d "$config_dir" ]]; then
        return
    fi

    echo "Copying config files from $config_dir to $WORKSPACE"
    for file in "$config_dir"/*; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            local target="$WORKSPACE/$filename"
            if [[ ! -e "$target" ]]; then
                cp "$file" "$target"
                echo "  Copied: $filename"
            fi
        elif [[ -d "$file" ]]; then
            local dirname=$(basename "$file")
            local target="$WORKSPACE/$dirname"
            if [[ ! -e "$target" ]]; then
                cp -r "$file" "$target"
                echo "  Copied: $dirname/"
            fi
        fi
    done
}

run_hook() {
    local hook_name="$1"
    local hook_script="$WORKSPACE/.sbx-here/hooks/$hook_name"

    if [[ -x "$hook_script" ]]; then
        # Run in a subshell to prevent hook failures/exits from killing this wrapper prematurely
        ( "$hook_script" ) || echo "Warning: Hook $hook_name exited with a non-zero status." >&2
    fi
}

# Short-circuit execution if the user only wanted to read the metadata state
if [[ "$NAME_ONLY" == true ]]; then
    if [[ -n "$SBX_NAME" ]]; then
        echo "$SBX_NAME"
        exit 0
    else
        # Silent exit status signaling unconfigured state to scripts
        exit 1
    fi
fi

# Interactive initialization block (Only triggers if state is empty)
if [[ -z "$SBX_NAME" ]]; then
    CREATE=true

    # Derive a Docker-safe default name from the current directory
    CLEAN_DIR=$(basename "$WORKSPACE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g')

    echo "No docker sandbox name found."
    echo "Select the target harness:"

    AGENT=$(select_harness)

    DEFAULT_NAME="${AGENT}-${CLEAN_DIR}"

    read -r -p "Enter sandbox name [$DEFAULT_NAME]: " USER_INPUT
    SBX_NAME="${USER_INPUT:-$DEFAULT_NAME}"

    # Persist tracking token based on context
    if [[ "$IN_GIT" == true ]]; then
        git config --local sbx.name "$SBX_NAME"
        git config --local sbx.agent "$AGENT"
        echo "Context bound to local git config."
    else
        echo "$SBX_NAME" > "$SBX_FILE"
        echo "Context bound to standalone file ($SBX_FILE)."
    fi
fi

# REMOVE sandbox and optionally clean up configuration
if [[ "$REMOVE" == true ]]; then
    if [[ -n "$SBX_NAME" ]]; then
        echo "Removing sandbox: $SBX_NAME"
        sbx rm "$SBX_NAME" || echo "Sandbox not found or already removed."
    fi

    if [[ "$CLEANUP_ONLY" == true ]]; then
        cleanup_config
        echo "Sandbox and configuration removal complete."
        exit 0
    fi
fi

# Create sandbox and copy config files if new
if [[ "$CREATE" == true ]]; then
    # Ensure AGENT is set before creating
    if [[ -z "$AGENT" ]]; then
        echo "Select the harness for this sandbox:"
        AGENT=$(select_harness)
    fi

    echo "Creating docker sandbox $SBX_NAME"
    create_sandbox "$SBX_NAME" "$AGENT" "$WORKSPACE"
    copy_config_files
fi

run_hook "pre-run"
trap 'run_hook "post-run"' EXIT

if [[ ${#AGENT_ARGS[@]} -gt 0 ]]; then
    sbx run --name "$SBX_NAME" -- "${AGENT_ARGS[@]}"
else
    sbx run --name "$SBX_NAME"
fi
