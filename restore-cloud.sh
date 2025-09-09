#!/bin/bash
# Version 5.2: Professionalization, dry-run mode, and error handling.
# Changes:
# - REMOVED: Syntax error (extra '}' at the end of the file).
# + ADDED: Professional error handling with 'trap', consistent with backup-cloud.sh.
# - Added --dry-run mode for simulation.
# - Better backup validation (collective errors).
# - Added check for free disk space.
# - Added verification of GPG private key availability before decryption.

# --- FLAG PARSING ---
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# --- LOAD CONFIGURATION ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/backup_restore.config" || { echo "Error: Could not load the configuration file."; exit 1; }
# ---

# --- Colors and logging ---
COLOR_RESET='\033[0m'; COLOR_GREEN='\033[0;32m'; COLOR_RED='\033[0;31m'; COLOR_YELLOW='\033[0;33m'; COLOR_BLUE='\033[0;34m'
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1${COLOR_RESET}"; }
log_info() { log "${COLOR_BLUE}$1"; }
log_success() { log "${COLOR_GREEN}✅ $1"; }
log_error() { log "${COLOR_RED}❌ $1"; }
log_warning() { log "${COLOR_YELLOW}⚠️  $1"; }
log_dry_run() { [[ "$DRY_RUN" == "true" ]] && log_info "DRY-RUN: $1"; }

# --- PROFESSIONAL ERROR HANDLING ---
errorHandler() {
    local exit_code=$?
    local line_num=$1
    local command=$2
    log_error "A critical error occurred on line $line_num: command '$command' returned with exit code $exit_code."
    exit $exit_code
}
trap 'errorHandler ${LINENO} "$BASH_COMMAND"' ERR
set -o pipefail
# ---

# --- HELPER FUNCTIONS ---
check_dependencies() {
    log_info "Checking dependencies (gh, tar)..."
    local missing=0
    for cmd in gh tar; do
        if ! command -v "$cmd" &> /dev/null; then log_error "Missing command: $cmd"; missing=1; fi
    done
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

validate_backup() {
    log_info "Validating the integrity of the unpacked backup..."
    local errors=()
    [[ ! -f "$BACKUP_DIR/apt_packages.txt" ]] && errors+=("Missing apt_packages.txt file")
    [[ ! -f "$BACKUP_DIR/system_info.txt" ]] && errors+=("Missing system_info.txt file")
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "The backup is incomplete. Errors: ${errors[*]}"
        return 1
    fi
    log_success "The backup appears to be complete."
    return 0
}

check_gpg_key() {
    if [[ -n "$GPG_RECIPIENT_EMAIL" ]]; then
        log_info "Checking for GPG private key availability..."
        if ! gpg --list-secret-keys "$GPG_RECIPIENT_EMAIL" &>/dev/null; then
            log_error "Private key for '$GPG_RECIPIENT_EMAIL' not found. Cannot decrypt the backup."
            return 1
        fi
        log_success "GPG private key is available."
    fi
}

# --- MAIN LOGIC ---
main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in --dry-run mode. No changes will be made."
    fi

    check_dependencies
    check_disk_space

    # --- Select backup to restore ---
    log_info "Fetching the list of available backups..."
    TAGS=$(gh release list --repo "$GH_REPO" --limit 10 --json tagName -q '.[].tagName')
    if [ -z "$TAGS" ]; then
        log_error "No backups (releases) found in the repository $GH_REPO."
        exit 1
    fi

    log_info "Select a backup to restore:"
    select SELECTED_TAG in $TAGS; do
        if [ -n "$SELECTED_TAG" ]; then
            log_info "Selected: $SELECTED_TAG"
            break
        else
            log_warning "Invalid selection. Please try again."
        fi
    done
    
    # --- Downloading and unpacking ---
    DOWNLOADED_ARCHIVE=$(ls -t backup_*.tar.gz* 2>/dev/null | head -n 1) # simulation for dry-run
    log_info "Downloading the archive ($SELECTED_TAG)..."
    log_dry_run "Would download the archive for tag $SELECTED_TAG"
    [[ "$DRY_RUN" == "false" ]] && gh release download "$SELECTED_TAG" --repo "$GH_REPO" --pattern "backup_*.tar.gz*" --clobber && DOWNLOADED_ARCHIVE=$(ls -t backup_*.tar.gz* 2>/dev/null | head -n 1)

    if [[ "$DOWNLOADED_ARCHIVE" == *.gpg ]]; then
        check_gpg_key || exit 1
        log_dry_run "Would decrypt and unpack $DOWNLOADED_ARCHIVE"
        [[ "$DRY_RUN" == "false" ]] && gpg --decrypt "$DOWNLOADED_ARCHIVE" | sudo tar --numeric-owner -xzf -
    else
        log_dry_run "Would unpack $DOWNLOADED_ARCHIVE"
        [[ "$DRY_RUN" == "false" ]] && sudo tar --numeric-owner -xzf "$DOWNLOADED_ARCHIVE"
    fi
    
    BACKUP_DIR=$(ls -d backup_*/ 2>/dev/null | head -n 1)
    if [ -z "$BACKUP_DIR" ]; then log_error "Unpacked folder not found." && exit 1; fi
    
    validate_backup || exit 1

    # --- User dialog ---
    # ... (logic for asking the user to continue can be added here) ...
    
    # --- SECTION 1: INSTALLING MISSING SOFTWARE ---
    log_info "SECTION 1: INSTALLING MISSING SOFTWARE"
    # ... (logic for installing software, e.g., apt, pip, go) ...
    
    # --- SECTION 2: RESTORING CONFIGURATION FILES ---
    log_info "SECTION 2: RESTORING CONFIGURATION FILES"
    for item_path in "${BACKUP_PATHS[@]}"; do
        src_path_basename=$(basename "$item_path")
        src_path_in_backup="$BACKUP_DIR/$src_path_basename"

        if [ -e "$src_path_in_backup" ]; then
            log_info "   -> Restoring: $item_path"
            log_dry_run "Would restore $src_path_in_backup to $item_path"
            if [[ "$DRY_RUN" == "false" ]]; then
                # Backing up the existing file before overwriting
                if [ -e "$item_path" ]; then
                    mv "$item_path" "${item_path}.before_restore_$(date +%s)"
                fi
                # Copying while preserving owner rights
                sudo cp -a "$src_path_in_backup" "$item_path"
            fi
        else
            log_warning "Source not found in backup for '$item_path'. Skipping."
        fi
    done

    log_success "Restore operation completed."
}

main
