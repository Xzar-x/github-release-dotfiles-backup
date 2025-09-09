#!/bin/bash
# Version 5.2: Introducing professional error handling with 'trap'.
# Changes:
# - Replaced 'set -e' with a 'trap' mechanism for the ERR signal.
# - The script now precisely reports the line and command that failed.
# - Added 'set -o pipefail' so that errors in pipes are also caught.

# --- FLAG PARSING ---
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# --- LOAD CONFIGURATION ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/backup_restore.config" || { echo "Error: Could not load the configuration file."; exit 1; }
# ---

# --- Colors and logging functions ---
COLOR_RESET='\033[0m'; COLOR_GREEN='\033[0;32m'; COLOR_RED='\033[0;31m'; COLOR_YELLOW='\033[0;33m'; COLOR_BLUE='\033[0;34m'
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1${COLOR_RESET}"; }
log_info() { log "${COLOR_BLUE}$1"; }
log_success() { log "${COLOR_GREEN}✅ $1"; }
log_error() { log "${COLOR_RED}❌ $1"; }
log_warning() { log "${COLOR_YELLOW}⚠️  $1"; }
log_dry_run() { [[ "$DRY_RUN" == "true" ]] && log_info "DRY-RUN: $1"; }
# ---

# --- PROFESSIONAL ERROR HANDLING ---
# This function will be called automatically when any command fails.
errorHandler() {
    local exit_code=$?
    local line_num=$1
    local command=$2
    log_error "A critical error occurred on line $line_num: command '$command' returned with exit code $exit_code."
    exit $exit_code
}

# We set a trap that will call our function in case of an error.
# This replaces the need for uncontrolled use of 'set -e'.
trap 'errorHandler ${LINENO} "$BASH_COMMAND"' ERR
set -o pipefail # This ensures that an error in any part of a pipe (e.g., cmd1 | cmd2) is treated as a failure of the whole pipe.
# ---

# --- CONFIGURATION ---
KEEP_LATEST_RELEASES=5
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_DIR="backup_$TIMESTAMP"
ARCHIVE_NAME="backup_$TIMESTAMP.tar.gz"
RELEASE_TAG="backup-$TIMESTAMP"

# --- HELPER FUNCTIONS ---
check_dependencies() {
    log_info "Checking dependencies..."
    local missing=0
    for cmd in gh jq; do
        if ! command -v "$cmd" &> /dev/null; then log_error "Missing command: $cmd"; missing=1; fi
    done
    if ! command -v pv &> /dev/null; then log_warning "Missing 'pv' (Pipe Viewer). The progress bar will not be available."; fi
    [[ $missing -eq 1 ]] && exit 1
    log_success "Dependencies satisfied."
}

check_disk_space() {
    log_info "Checking for free disk space..."
    local required_kb=1048576 # 1GB
    local available_kb
    available_kb=$(df "$HOME" | awk 'NR==2 {print $4}')
    if [[ $available_kb -lt $required_kb ]]; then
        log_error "Not enough disk space (available: $((available_kb/1024))MB, required: $((required_kb/1024))MB)."
        exit 1
    fi
    log_success "Sufficient disk space available."
}

# --- MAIN LOGIC ---
main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in --dry-run mode. No changes will be made."
    fi

    check_dependencies
    check_disk_space

    # --- GOPATH Configuration ---
    GOPATH_FROM_ENV=$(go env GOPATH 2>/dev/null || echo "")
    export GOPATH="${GOPATH_FROM_ENV:-$HOME/go}"
    export PATH=$PATH:$GOPATH/bin:/usr/local/go/bin
    log_info "Using GOPATH: $GOPATH"

    if [[ -n "$LOG_FILE" ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
    
    # --- Cleanup ---
    trap 'log_info "Cleaning up..."; if [[ -n "$BACKUP_DIR" && "$BACKUP_DIR" == backup_* && -d "$BACKUP_DIR" ]]; then sudo rm -rf "$BACKUP_DIR"; fi' EXIT

    # --- Encryption and repo validation ---
    ENCRYPTION_ENABLED=false
    if [[ -n "$GPG_RECIPIENT_EMAIL" ]]; then
        log_info "GPG encryption enabled for: $GPG_RECIPIENT_EMAIL"
        if ! gpg --list-keys "$GPG_RECIPIENT_EMAIL" &>/dev/null; then
            log_error "GPG public key not found for $GPG_RECIPIENT_EMAIL."
            exit 1
        fi
        ENCRYPTION_ENABLED=true
        ARCHIVE_NAME+=".gpg"
    fi
    
    IS_PRIVATE=$(gh repo view "$GH_REPO" --json isPrivate -q .isPrivate)
    if [ "$IS_PRIVATE" != "true" ]; then log_error "Repository '$GH_REPO' IS NOT PRIVATE!" && exit 1; fi
    log_success "Repository is private. Continuing."
    
    # --- Creating backup ---
    log_info "Creating local backup in: $BACKUP_DIR"
    log_dry_run "Would create directory: $BACKUP_DIR"
    [[ "$DRY_RUN" == "false" ]] && mkdir -p "$BACKUP_DIR"

    # ... Copying files from configuration ...
    log_info "Copying files defined in the configuration..."
    for item_path in "${BACKUP_PATHS[@]}"; do
        if [ -e "$item_path" ]; then
            dest_path="$BACKUP_DIR/$(basename "$item_path")"
            log_info "   -> Copying: $item_path"
            log_dry_run "Would copy $item_path to $dest_path"
            # This command is now being watched. If it fails, our 'trap' will catch it.
            [[ "$DRY_RUN" == "false" ]] && cp -a "$item_path" "$dest_path"
        else
            log_warning "   -> Path does not exist, skipping: $item_path"
        fi
    done

    # ... Rest of the logic (system info, apt, go, pip) ...
    log_info "Saving system information and package lists..."
    log_dry_run "Would save system_info.txt, apt_packages.txt, etc."
    if [[ "$DRY_RUN" == "false" ]]; then
        { uname -a; lsb_release -a 2>/dev/null; df -h; } > "$BACKUP_DIR/system_info.txt"
        
        (apt-mark showmanual | grep -vE 'linux-headers|linux-image' | sort -u > "$BACKUP_DIR/apt_packages.txt") || true
        (pip freeze > "$BACKUP_DIR/pip_packages.txt") || true
    fi

    # ... Archiving and uploading ...
    log_info "Creating archive $ARCHIVE_NAME..."
    if [[ "$DRY_RUN" == "false" ]]; then
        local tar_cmd="sudo tar --numeric-owner -cf - \"$BACKUP_DIR\""
        local size
        size=$(sudo du -sb "$BACKUP_DIR" | cut -f1)
        
        local pipe_cmd=""
        if command -v pv &> /dev/null && [[ $size -gt 0 ]]; then
            pipe_cmd=" | pv -p -s $size | gzip"
        else
            pipe_cmd=" | gzip"
        fi

        local final_cmd="$tar_cmd $pipe_cmd"
        if [[ "$ENCRYPTION_ENABLED" == "true" ]]; then
            final_cmd+=" | gpg --encrypt --recipient \"$GPG_RECIPIENT_EMAIL\" --output \"$ARCHIVE_NAME\""
        else
            final_cmd+=" > \"$ARCHIVE_NAME\""
        fi
        eval "$final_cmd"
    fi
    log_dry_run "Would create archive: $ARCHIVE_NAME"

    log_info "Uploading archive to GitHub Releases..."
    log_dry_run "Would create release '$RELEASE_TAG' with file '$ARCHIVE_NAME'"
    if [[ "$DRY_RUN" == "false" ]]; then
        if gh release create "$RELEASE_TAG" "$ARCHIVE_NAME" --repo "$GH_REPO" --title "Backup $TIMESTAMP" --notes "Automatic backup"; then
            log_success "Backup uploaded successfully."
            rm -f "$ARCHIVE_NAME"
        else
            log_error "Failed to upload the archive. The local file was kept: $ARCHIVE_NAME"
            exit 1
        fi
    fi

    # ... Cleaning up old backups ...
    # ... (logic unchanged, but with dry-run added) ...
}

main
