#!/bin/bash
# Version 7.1: Shellcheck fixes (SC2034).

# ... (flag, config loading, logging, and error handler sections unchanged) ...
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then DRY_RUN=true; fi
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/backup_restore.config" || { echo "Error: Could not load configuration file."; exit 1; }
COLOR_RESET='\033[0m'; COLOR_GREEN='\033[0;32m'; COLOR_RED='\033[0;31m'; COLOR_YELLOW='\033[0;33m'; COLOR_BLUE='\033[0;34m'
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1${COLOR_RESET}"; }
log_info() { log "${COLOR_BLUE}$1"; }; log_success() { log "${COLOR_GREEN}✅ $1"; }; log_error() { log "${COLOR_RED}❌ $1"; }; log_warning() { log "${COLOR_YELLOW}⚠️  $1"; }; log_dry_run() { [[ "$DRY_RUN" == "true" ]] && log_info "DRY-RUN: $1"; }
errorHandler() { local exit_code=$?; local line_num=$1; local command=$2; log_error "A critical error occurred on line $line_num: command '$command' returned error code $exit_code."; exit $exit_code; }
trap 'errorHandler ${LINENO} "$BASH_COMMAND"' ERR
set -o pipefail

# --- CONFIGURATION ---
KEEP_LATEST_RELEASES=5
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_DIR="backup_$TIMESTAMP"
ARCHIVE_NAME="backup_$TIMESTAMP.tar.gz"
RELEASE_TAG="backup-$TIMESTAMP"

# --- HELPER FUNCTIONS ---
check_dependencies() {
    log_info "Checking dependencies..."
    # FIX SC2034: Removed unused 'missing' variable.
    for cmd in gh jq tar gzip flatpak snap; do
        if ! command -v "$cmd" &> /dev/null; then log_warning "Command not found: $cmd (functionality may be limited)"; fi
    done
    if ! command -v pv &> /dev/null; then log_warning "'pv' (Pipe Viewer) not found. The progress bar will not be available."; fi
    log_success "Dependency check finished."
}
# ... (rest of the script unchanged) ...
check_disk_space() { log_info "Checking for free disk space..."; local required_kb=1048576; local available_kb; available_kb=$(df "$HOME" | awk 'NR==2 {print $4}'); if [[ $available_kb -lt $required_kb ]]; then log_error "Not enough disk space (available: $((available_kb/1024))MB, required: $((required_kb/1024))MB)."; exit 1; fi; log_success "Sufficient disk space available."; }
cleanup_old_releases() { log_info "Cleaning up old backups (I will keep the ${KEEP_LATEST_RELEASES} latest)..."; local all_tags_array=(); mapfile -t all_tags_array < <(gh release list --repo "$GH_REPO" --limit 100 --json tagName -q '.[].tagName' 2>/dev/null); if [ ${#all_tags_array[@]} -eq 0 ]; then log_warning "No releases found. Skipping cleanup."; return 0; fi; local total_releases=${#all_tags_array[@]}; if (( total_releases <= KEEP_LATEST_RELEASES )); then log_success "Found $total_releases backups. Nothing to clean up."; return 0; fi; log_info "Found $total_releases backups. Starting removal..."; local tags_to_delete=("${all_tags_array[@]:KEEP_LATEST_RELEASES}"); for tag in "${tags_to_delete[@]}"; do log_warning "   -> Scheduled for deletion: $tag"; log_dry_run "I would delete the release with tag: $tag"; if [[ "$DRY_RUN" == "false" ]]; then if gh release delete "$tag" --repo "$GH_REPO" --yes --cleanup-tag; then log_success "   -> Deleted: $tag"; else log_error "   -> Failed to delete: $tag"; fi; fi; done; log_success "Cleanup of old backups finished."; }
backup_package_lists() { log_info "Saving lists of installed packages..."; log_dry_run "I would save the lists of apt, flatpak, snap packages."; if [[ "$DRY_RUN" == "false" ]]; then (dpkg --get-selections | grep -v deinstall | awk '{print $1}' > "$BACKUP_DIR/apt_packages.txt") || true; if command -v flatpak &> /dev/null; then (flatpak list --app --columns=application > "$BACKUP_DIR/flatpak_apps.txt") || true; fi; if command -v snap &> /dev/null; then (snap list | awk 'NR>1 {print $1}' > "$BACKUP_DIR/snap_apps.txt") || true; fi; fi; }
backup_environment_metadata() { log_info "Saving environment metadata..."; log_dry_run "I would save the environment_metadata.txt file"; if [[ "$DRY_RUN" == "false" ]]; then { echo "=== PYTHON ENVIRONMENT ==="; python3 --version 2>/dev/null || echo "Python3 not installed"; pip list 2>/dev/null || echo "Pip not available"; echo -e "\n=== NODE ENVIRONMENT ==="; node --version 2>/dev/null || echo "Node not installed"; npm --version 2>/dev/null || echo "NPM not available"; echo -e "\n=== GO ENVIRONMENT ==="; go version 2>/dev/null || echo "Go not installed"; echo -e "\n=== SHELL ENVIRONMENT ==="; echo "SHELL: $SHELL"; echo "PATH: $PATH"; } > "$BACKUP_DIR/environment_metadata.txt"; fi; }
main() { if [[ "$DRY_RUN" == "true" ]]; then log_warning "Running in --dry-run mode."; fi; check_dependencies; check_disk_space; if [[ -n "$LOG_FILE" ]]; then exec > >(tee -a "$LOG_FILE") 2>&1; fi; trap 'log_info "Cleaning up..."; if [[ -n "$BACKUP_DIR" && "$BACKUP_DIR" == backup_* && -d "$BACKUP_DIR" ]]; then sudo rm -rf "$BACKUP_DIR"; fi' EXIT; ENCRYPTION_ENABLED=false; if [[ -n "$GPG_RECIPIENT_EMAIL" ]]; then log_info "GPG encryption enabled for: $GPG_RECIPIENT_EMAIL"; if ! gpg --list-keys "$GPG_RECIPIENT_EMAIL" &>/dev/null; then log_error "GPG key for $GPG_RECIPIENT_EMAIL not found."; exit 1; fi; ENCRYPTION_ENABLED=true; ARCHIVE_NAME+=".gpg"; fi; IS_PRIVATE=$(gh repo view "$GH_REPO" --json isPrivate -q .isPrivate); if [ "$IS_PRIVATE" != "true" ]; then log_error "Repository '$GH_REPO' IS NOT PRIVATE!"; exit 1; fi; log_success "Repository is private."; log_info "Creating a local backup in: $BACKUP_DIR"; log_dry_run "I would create the directory: $BACKUP_DIR"; [[ "$DRY_RUN" == "false" ]] && mkdir -p "$BACKUP_DIR"; log_info "Copying files defined in the configuration..."; for item_path in "${BACKUP_PATHS[@]}"; do if [ -e "$item_path" ]; then dest_path="$BACKUP_DIR/$(basename "$item_path")"; log_info "   -> Copying: $item_path"; log_dry_run "I would copy $item_path to $dest_path"; [[ "$DRY_RUN" == "false" ]] && cp -a "$item_path" "$dest_path"; else log_warning "   -> Path does not exist, skipping: $item_path"; fi; done; log_info "Saving system information and package lists..."; log_dry_run "I would save system_info.txt"; if [[ "$DRY_RUN" == "false" ]]; then { uname -a; lsb_release -a 2>/dev/null; df -h; } > "$BACKUP_DIR/system_info.txt"; fi; backup_package_lists; backup_environment_metadata; log_info "Creating archive $ARCHIVE_NAME..."; if [[ "$DRY_RUN" == "false" ]]; then local tar_cmd="sudo tar --numeric-owner -cf - \"$BACKUP_DIR\""; local size; size=$(sudo du -sb "$BACKUP_DIR" | cut -f1); local pipe_cmd=""; if command -v pv &> /dev/null && [[ $size -gt 0 ]]; then pipe_cmd=" | pv -p -s $size | gzip"; else pipe_cmd=" | gzip"; fi; local final_cmd="$tar_cmd $pipe_cmd"; if [[ "$ENCRYPTION_ENABLED" == "true" ]]; then final_cmd+=" | gpg --encrypt --recipient \"$GPG_RECIPIENT_EMAIL\" --output \"$ARCHIVE_NAME\""; else final_cmd+=" > \"$ARCHIVE_NAME\""; fi; eval "$final_cmd"; fi; log_dry_run "I would create the archive: $ARCHIVE_NAME"; log_info "Uploading the archive to GitHub Releases..."; log_dry_run "I would create release '$RELEASE_TAG' with the file '$ARCHIVE_NAME'"; if [[ "$DRY_RUN" == "false" ]]; then if gh release create "$RELEASE_TAG" "$ARCHIVE_NAME" --repo "$GH_REPO" --title "Backup $TIMESTAMP" --notes "Automatic backup"; then log_success "Backup uploaded successfully."; rm -f "$ARCHIVE_NAME"; else log_error "Failed to upload the archive."; exit 1; fi; fi; cleanup_old_releases; }
main
