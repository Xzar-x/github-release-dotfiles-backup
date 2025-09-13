#!/bin/bash
# Version 7.2 "Diamond": Further security and diagnostic improvements.
# Changes: Better .deb verification, precise health-check for Go, post-operation summary.

# ... (flag, config loading, logging, and error handler sections unchanged) ...
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then DRY_RUN=true; fi
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/backup_restore.config" || { echo "Error: Could not load configuration file."; exit 1; }
COLOR_RESET='\033[0m'; COLOR_GREEN='\033[0;32m'; COLOR_RED='\033[0;31m'; COLOR_YELLOW='\033[0;33m'; COLOR_BLUE='\033[0;34m'
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1${COLOR_RESET}"; }
log_info() { log "${COLOR_BLUE}$1"; }; log_success() { log "${COLOR_GREEN}✅ $1"; }; log_error() { log "${COLOR_RED}❌ $1"; }; log_warning() { log "${COLOR_YELLOW}⚠️  $1"; }; log_dry_run() { [[ "$DRY_RUN" == "true" ]] && log_info "DRY-RUN: $1"; }
errorHandler() { local exit_code=$?; local line_num=$1; local command=$2; log_error "A critical error occurred on line $line_num: '$command' returned code $exit_code."; log_info "Consider using the rollback_last_restore function to undo changes to configuration files."; exit $exit_code; }
trap 'errorHandler ${LINENO} "$BASH_COMMAND"' ERR
set -o pipefail

# --- GLOBAL VARIABLES ---
CURRENT_STEP=0
TOTAL_STEPS=0
BACKUP_DIR=""

# ... (check_dependencies, check_disk_space, validate_backup, check_gpg_key unchanged) ...
check_dependencies() { log_info "Checking dependencies..."; local missing=0; for cmd in gh tar dpkg git wget npm pip go lsb_release dpkg-sig flatpak snap; do if ! command -v "$cmd" &> /dev/null; then log_warning "Command not found: $cmd"; missing=1; fi; done; [[ $missing -eq 1 ]] && log_error "Key dependencies are missing. Please install them and try again." && exit 1; log_success "Dependencies satisfied."; }
check_disk_space() { log_info "Checking for free disk space..."; local required_kb=1048576; local available_kb; available_kb=$(df "$HOME" | awk 'NR==2 {print $4}'); if [[ $available_kb -lt $required_kb ]]; then log_error "Not enough disk space (available: $((available_kb/1024))MB, required: $((required_kb/1024))MB)."; exit 1; fi; log_success "Sufficient disk space available."; }
validate_backup() { log_info "Validating integrity of the unpacked backup..."; if [[ ! -f "$BACKUP_DIR/apt_packages.txt" || ! -f "$BACKUP_DIR/system_info.txt" ]]; then log_error "The backup is incomplete."; return 1; fi; log_success "The backup appears to be complete."; return 0; }
check_gpg_key() { if [[ -n "$GPG_RECIPIENT_EMAIL" ]]; then log_info "Checking GPG key..."; if ! gpg --list-secret-keys "$GPG_RECIPIENT_EMAIL" &>/dev/null; then log_error "Private key for '$GPG_RECIPIENT_EMAIL' not found."; return 1; fi; log_success "GPG private key available."; fi; }
pre_flight_check() { log_info "Performing system pre-flight check..."; local current_distro; current_distro=$(lsb_release -si 2>/dev/null || echo "Unknown"); if [[ -f "$BACKUP_DIR/system_info.txt" ]]; then local backup_distro; backup_distro=$(grep -E "Distributor ID" "$BACKUP_DIR/system_info.txt" | cut -d: -f2 | tr -d ' '); if [[ -n "$backup_distro" && "$current_distro" != "$backup_distro" ]]; then log_warning "Target system ($current_distro) differs from the source system ($backup_distro)."; read -r -p "Are you sure you want to continue? [Y/N]: " consent && [[ "${consent^^}" != "Y" ]] && exit 1; fi; fi; log_success "Pre-flight check completed successfully."; }
# ... (create_system_snapshot, rollback_last_restore unchanged) ...
create_system_snapshot() { local snapshot_base_dir="$HOME/.backup_snapshots"; local snapshot_dir; snapshot_dir="$snapshot_base_dir/snapshot_$(date +%s)"; mkdir -p "$snapshot_base_dir"; log_info "Creating a snapshot of configuration files in: $snapshot_dir"; log_dry_run "I would create a snapshot for ${#BACKUP_PATHS[@]} paths."; if [[ "$DRY_RUN" == "false" ]]; then for path in "${BACKUP_PATHS[@]}"; do if [[ -e "$path" ]]; then mkdir -p "$snapshot_dir/$(dirname "$path")"; cp -a "$path" "$snapshot_dir/$path"; fi; done; echo "$snapshot_dir" > "$snapshot_base_dir/.last_restore_snapshot"; fi; }
rollback_last_restore() { local snapshot_file="$HOME/.backup_snapshots/.last_restore_snapshot"; if [[ ! -f "$snapshot_file" ]]; then log_error "Information about the last snapshot was not found."; return 1; fi; local snapshot_dir; snapshot_dir=$(cat "$snapshot_file" 2>/dev/null); if [[ -d "$snapshot_dir" ]]; then log_warning "Restoring files from snapshot: $snapshot_dir"; read -r -p "This will overwrite current files. Continue? [Y/N]: " consent; if [[ "${consent^^}" == "Y" ]]; then rsync -a "$snapshot_dir/" /; log_success "Rollback of configuration files completed."; else log_error "Rollback canceled."; fi; else log_error "Snapshot directory '$snapshot_dir' does not exist."; fi; }

# --- IMPROVED DIAGNOSTIC FUNCTIONS ---
post_restore_check() {
    log_info "Performing post-restore health check..."
    local failed_tools=()
    for tool in git npm pip go; do if ! command -v "$tool" &> /dev/null; then failed_tools+=("$tool"); fi; done

    # Smart check for Go tools
    if command -v go &> /dev/null; then
        # The list of Go tools can come from a log file or the configuration
        local go_tools_list=()
        if [[ -f "$BACKUP_DIR/.log_go_packages.txt" ]]; then
            mapfile -t go_tools_list < "$BACKUP_DIR/.log_go_packages.txt"
        else
            go_tools_list=("${GO_TOOLS_TO_BACKUP[@]}")
        fi

        for tool_path in "${go_tools_list[@]}"; do
            local tool_binary; tool_binary=$(basename "$tool_path" | cut -d'@' -f1)
            local go_bin_path; go_bin_path=$(go env GOPATH)/bin
            if [[ ! -x "$go_bin_path/$tool_binary" ]]; then failed_tools+=("$tool_binary (go)"); fi
        done
    fi

    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        log_error "The following tools are not working or are missing: ${failed_tools[*]}"
        log_info "Re-run the installation for selected sections or check the logs."
        return 1
    fi
    log_success "All key tools are working correctly."
    return 0
}

show_restore_summary() {
    log_info "==================================="
    log_info "====== RESTORE SUMMARY ======"
    log_info "==================================="
    
    local total_apt=0 total_deb=0 total_git=0 total_pip=0 total_npm=0 total_go=0 total_flatpak=0 total_snap=0
    
    [[ -f "$BACKUP_DIR/apt_packages.txt" ]] && total_apt=$(wc -l < "$BACKUP_DIR/apt_packages.txt")
    [[ -f "$BACKUP_DIR/.log_deb_urls.txt" ]] && total_deb=$(wc -l < "$BACKUP_DIR/.log_deb_urls.txt")
    [[ -f "$BACKUP_DIR/.log_git_urls.txt" ]] && total_git=$(wc -l < "$BACKUP_DIR/.log_git_urls.txt")
    [[ -f "$BACKUP_DIR/.log_pip_packages.txt" ]] && total_pip=$(wc -l < "$BACKUP_DIR/.log_pip_packages.txt")
    [[ -f "$BACKUP_DIR/.log_npm_global_packages.txt" ]] && total_npm=$(wc -l < "$BACKUP_DIR/.log_npm_global_packages.txt")
    [[ -f "$BACKUP_DIR/.log_go_packages.txt" ]] && total_go=$(wc -l < "$BACKUP_DIR/.log_go_packages.txt")
    [[ -f "$BACKUP_DIR/flatpak_apps.txt" ]] && total_flatpak=$(wc -l < "$BACKUP_DIR/flatpak_apps.txt")
    [[ -f "$BACKUP_DIR/snap_apps.txt" ]] && total_snap=$(wc -l < "$BACKUP_DIR/snap_apps.txt")

    echo -e "${COLOR_GREEN}📦 APT Packages:${COLOR_RESET}\t\t$total_apt"
    echo -e "${COLOR_GREEN}📦 .deb Packages:${COLOR_RESET}\t\t$total_deb"
    echo -e "${COLOR_GREEN}📦 Flatpak Apps:${COLOR_RESET}\t$total_flatpak"
    echo -e "${COLOR_GREEN}📦 Snap Apps:${COLOR_RESET}\t\t$total_snap"
    echo -e "${COLOR_GREEN}🔧 Git Repositories:${COLOR_RESET}\t$total_git"
    echo -e "${COLOR_GREEN}🐍 Python Packages (pip):${COLOR_RESET}\t$total_pip"
    echo -e "${COLOR_GREEN}📦 Node.js Packages (npm):${COLOR_RESET}\t$total_npm"
    echo -e "${COLOR_GREEN}🚀 Go Tools:${COLOR_RESET}\t\t$total_go"
    echo -e "${COLOR_GREEN}📁 Configuration Files:${COLOR_RESET}\t${#BACKUP_PATHS[@]}"
    
    log_info "System snapshot available at: $(cat "$HOME/.backup_snapshots/.last_restore_snapshot" 2>/dev/null || echo "None")"
    log_info "If you have issues with configuration files, use: ./restore-cloud.sh --rollback"
}

# --- IMPROVED RESTORE FUNCTIONS ---
verify_deb_package() {
    local deb_file="$1"
    if ! dpkg --info "$deb_file" &> /dev/null; then log_error "Package $deb_file is corrupted or invalid."; return 1; fi
    if command -v dpkg-sig &> /dev/null; then
        if ! dpkg-sig --verify "$deb_file" &> /dev/null; then
            log_warning "Package $deb_file does not have a valid signature or is not signed."
            read -r -p "Do you still want to install? [Y/N]: " consent
            [[ "${consent^^}" != "Y" ]] && return 1
        else
            log_success "The signature of package $deb_file is valid."
        fi
    else
        log_warning "'dpkg-sig' not found. Skipping signature verification for $deb_file."
    fi
    return 0
}

# ... (rest of functions and main logic unchanged, but they will call the new versions of `verify_deb_package` and `post_restore_check`) ...
restore_apt_packages() { log_info "Preparing to install APT packages..."; mapfile -t required_packages < "$BACKUP_DIR/apt_packages.txt"; mapfile -t installed_packages < <(dpkg --get-selections | grep -v deinstall | awk '{print $1}'); local missing_packages=(); for pkg in "${required_packages[@]}"; do if ! [[ " ${installed_packages[*]} " =~ \ ${pkg}\  ]]; then missing_packages+=("$pkg"); fi; done; if [ ${#missing_packages[@]} -eq 0 ]; then log_success "All APT packages are already installed."; return 0; fi; log_warning "The script plans to install ${#missing_packages[@]} missing APT packages."; log_dry_run "I would execute 'sudo apt-get install -y ...'"; if [[ "$DRY_RUN" == "false" ]]; then sudo apt-get update; sudo apt-get install -y "${missing_packages[@]}"; fi; log_success "APT packages installed."; }
restore_deb_packages() { local log_file="$BACKUP_DIR/.log_deb_urls.txt"; if [[ ! -f "$log_file" ]]; then log_info "File .log_deb_urls.txt not found, skipping."; return 0; fi; log_info "Analyzing .deb packages..."; local urls_to_install=(); mapfile -t deb_urls < "$log_file"; for url in "${deb_urls[@]}"; do local pkg_name; pkg_name=$(basename "$url" | cut -d'_' -f1); if ! dpkg -s "$pkg_name" &> /dev/null; then urls_to_install+=("$url"); fi; done; if [ ${#urls_to_install[@]} -eq 0 ]; then log_success "All .deb packages are already installed."; return 0; fi; log_warning "The following .deb packages are scheduled for download and installation:"; printf " - %s\n" "${urls_to_install[@]}"; read -r -p "Continue? [Y/N]: " consent && [[ "${consent^^}" != "Y" ]] && { log_error "Installation canceled."; return 1; }; local TEMP_DIR; TEMP_DIR=$(mktemp -d); trap 'log_info "Cleaning up..."; rm -rf "$TEMP_DIR"' RETURN EXIT; log_info "Downloading packages to $TEMP_DIR..."; log_dry_run "I would download ${#urls_to_install[@]} .deb files"; if [[ "$DRY_RUN" == "false" ]]; then wget -P "$TEMP_DIR" "${urls_to_install[@]}"; sudo dpkg --configure -a; for deb_file in "$TEMP_DIR"/*.deb; do if verify_deb_package "$deb_file"; then log_info "Installing $deb_file..."; sudo dpkg -i --force-confask "$deb_file"; fi; done; sudo apt-get install -f -y; fi; log_success ".deb packages installed."; }
restore_git_repos() { local log_file="$BACKUP_DIR/.log_git_urls.txt"; if [[ ! -f "$log_file" ]]; then log_info "File .log_git_urls.txt not found, skipping."; return 0; fi; local target_dir="$HOME/Desktop/Git_repo"; log_info "Analyzing Git repositories to clone (target: $target_dir)..."; mkdir -p "$target_dir"; local repos_to_clone=(); mapfile -t git_urls < "$log_file"; for url in "${git_urls[@]}"; do local repo_name; repo_name=$(basename "$url" .git); if [[ ! -d "$target_dir/$repo_name" ]]; then repos_to_clone+=("$url"); fi; done; if [ ${#repos_to_clone[@]} -eq 0 ]; then log_success "All Git repositories are already cloned."; return 0; fi; log_warning "The following repositories are scheduled to be cloned to '$target_dir':"; printf " - %s\n" "${repos_to_clone[@]}"; read -r -p "Continue? [Y/N]: " consent && [[ "${consent^^}" != "Y" ]] && { log_error "Cloning canceled."; return 1; }; log_dry_run "I would clone ${#repos_to_clone[@]} repositories"; if [[ "$DRY_RUN" == "false" ]]; then for url in "${repos_to_clone[@]}"; do log_info "   -> Cloning: $url"; git clone "$url" "$target_dir/$(basename "$url" .git)"; done; fi; log_success "Git repositories cloned."; }
restore_pip_packages() { local log_file="$BACKUP_DIR/.log_pip_packages.txt"; if [[ ! -f "$log_file" ]]; then log_info "File .log_pip_packages.txt not found, skipping."; return 0; fi; log_info "Preparing to install PIP packages..."; log_dry_run "I would install packages from $log_file"; if [[ "$DRY_RUN" == "false" ]]; then xargs -a "$log_file" pip install --user; fi; log_success "PIP packages installed."; }
restore_npm_packages() { local log_file="$BACKUP_DIR/.log_npm_global_packages.txt"; if [[ ! -f "$log_file" ]]; then log_info "File .log_npm_global_packages.txt not found, skipping."; return 0; fi; log_info "Preparing to install global NPM packages..."; log_dry_run "I would globally install packages from $log_file"; if [[ "$DRY_RUN" == "false" ]]; then xargs -a "$log_file" sudo npm install -g; fi; log_success "Global NPM packages installed."; }
restore_go_packages() { local log_file="$BACKUP_DIR/.log_go_packages.txt"; if [[ ! -f "$log_file" ]]; then log_warning "File .log_go_packages.txt not found, using the list from configuration."; if [ ${#GO_TOOLS_TO_BACKUP[@]} -eq 0 ]; then log_info "No Go tools in configuration. Skipping."; return 0; fi; log_dry_run "I would install Go tools from the configuration."; if [[ "$DRY_RUN" == "false" ]]; then for tool in "${GO_TOOLS_TO_BACKUP[@]}"; do go install "$tool"; done; fi; else log_info "Preparing to install Go tools..."; log_dry_run "I would install Go tools from $log_file"; if [[ "$DRY_RUN" == "false" ]]; then xargs -a "$log_file" -n 1 go install; fi; fi; log_success "Go tools installed."; }
restore_flatpak_apps() { local log_file="$BACKUP_DIR/flatpak_apps.txt"; if [[ ! -f "$log_file" ]]; then log_info "File flatpak_apps.txt not found, skipping."; return 0; fi; log_info "Preparing to install Flatpak applications..."; log_dry_run "I would install applications from $log_file"; if [[ "$DRY_RUN" == "false" ]] && command -v flatpak &> /dev/null; then xargs -a "$log_file" -r flatpak install -y; fi; log_success "Flatpak applications installed."; }
restore_snap_apps() { local log_file="$BACKUP_DIR/snap_apps.txt"; if [[ ! -f "$log_file" ]]; then log_info "File snap_apps.txt not found, skipping."; return 0; fi; log_info "Preparing to install Snap applications..."; log_dry_run "I would install applications from $log_file"; if [[ "$DRY_RUN" == "false" ]] && command -v snap &> /dev/null; then xargs -a "$log_file" -r sudo snap install; fi; log_success "Snap applications installed."; }
restore_config_files() { ((CURRENT_STEP++)); log_info "Step ${CURRENT_STEP}/${TOTAL_STEPS}: RESTORING CONFIGURATION FILES"; create_system_snapshot; for item_path in "${BACKUP_PATHS[@]}"; do local src_path_in_backup; src_path_in_backup="$BACKUP_DIR/$(basename "$item_path")"; if [ -e "$src_path_in_backup" ]; then log_info "   -> Restoring: $item_path"; log_dry_run "I would restore $src_path_in_backup to $item_path"; if [[ "$DRY_RUN" == "false" ]]; then if [ -e "$item_path" ]; then mv "$item_path" "${item_path}.before_restore_$(date +%s)"; fi; sudo cp -a "$src_path_in_backup" "$item_path"; fi; fi; done; }
show_restore_menu() { log_info "Select sections to restore:"; PS3="Your choice: "; options=("All (recommended)" "Configuration files only" "System packages only (APT, DEB, Flatpak, Snap)" "Development environment only (Git, Pip, Npm, Go)" "Cancel"); select opt in "${options[@]}"; do case $opt in "All (recommended)") TOTAL_STEPS=4; full_restore; break ;; "Configuration files only") TOTAL_STEPS=1; restore_config_files; break ;; "System packages only (APT, DEB, Flatpak, Snap)") TOTAL_STEPS=1; ((CURRENT_STEP++)); log_info "Step ${CURRENT_STEP}/${TOTAL_STEPS}: INSTALLING SYSTEM PACKAGES"; restore_apt_packages; restore_deb_packages; restore_flatpak_apps; restore_snap_apps; break ;; "Development environment only (Git, Pip, Npm, Go)") TOTAL_STEPS=1; ((CURRENT_STEP++)); log_info "Step ${CURRENT_STEP}/${TOTAL_STEPS}: RESTORING DEVELOPMENT ENVIRONMENT"; restore_git_repos; restore_pip_packages; restore_npm_packages; restore_go_packages; break ;; "Cancel") log_info "Operation canceled."; exit 0 ;; *) log_warning "Invalid choice.";; esac; done; }
full_restore() { restore_config_files; ((CURRENT_STEP++)); log_info "Step ${CURRENT_STEP}/${TOTAL_STEPS}: INSTALLING SYSTEM PACKAGES"; restore_apt_packages; restore_deb_packages; restore_flatpak_apps; restore_snap_apps; ((CURRENT_STEP++)); log_info "Step ${CURRENT_STEP}/${TOTAL_STEPS}: RESTORING DEVELOPMENT ENVIRONMENT"; restore_git_repos; restore_pip_packages; restore_npm_packages; restore_go_packages; }

main() {
    if [[ "$1" == "--rollback" ]]; then rollback_last_restore; exit 0; fi
    if [[ "$DRY_RUN" == "true" ]]; then log_warning "Running in --dry-run mode."; fi
    check_dependencies; check_disk_space
    log_info "Fetching list of available backups..."; local TAGS; TAGS=$(gh release list --repo "$GH_REPO" --limit 10 --json tagName -q '.[].tagName'); if [ -z "$TAGS" ]; then log_error "No backups found."; exit 1; fi
    log_info "Select a backup to restore:"; select SELECTED_TAG in $TAGS; do if [ -n "$SELECTED_TAG" ]; then log_info "Selected: $SELECTED_TAG"; break; else log_warning "Invalid choice."; fi; done
    log_info "Downloading archive ($SELECTED_TAG)..."; log_dry_run "I would download the archive"; if [[ "$DRY_RUN" == "false" ]]; then gh release download "$SELECTED_TAG" --repo "$GH_REPO" --pattern "backup_*.tar.gz*" --clobber; fi
    local DOWNLOADED_ARCHIVE; DOWNLOADED_ARCHIVE=$(find . -maxdepth 1 -name "backup_*.tar.gz*" -print -quit); if [[ -z "$DOWNLOADED_ARCHIVE" && "$DRY_RUN" == "false" ]]; then log_error "Failed to download the archive."; exit 1; fi
    if [[ "$DOWNLOADED_ARCHIVE" == *.gpg ]]; then check_gpg_key || exit 1; log_dry_run "I would decrypt and unpack $DOWNLOADED_ARCHIVE"; [[ "$DRY_RUN" == "false" ]] && gpg --decrypt "$DOWNLOADED_ARCHIVE" | sudo tar --numeric-owner -xzf -; else log_dry_run "I would unpack $DOWNLOADED_ARCHIVE"; [[ "$DRY_RUN" == "false" ]] && sudo tar --numeric-owner -xzf "$DOWNLOADED_ARCHIVE"; fi
    BACKUP_DIR=$(find . -maxdepth 1 -type d -name "backup_*" -print -quit); if [ -z "$BACKUP_DIR" ]; then log_error "Unpacked folder not found."; exit 1; fi
    validate_backup || exit 1; pre_flight_check
    show_restore_menu
    ((CURRENT_STEP++)); log_info "Step ${CURRENT_STEP}/${TOTAL_STEPS}: FINAL CHECK"; post_restore_check
    show_restore_summary # NEW: Calling the summary
    log_success "Restore operation completed successfully."
}
main "$@"

