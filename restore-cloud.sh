#!/bin/bash
# Wersja 7.2 "Diamond": Dalsze ulepszenia bezpieczeństwa i diagnostyki.
# Zmiany: Lepsza weryfikacja .deb, precyzyjny health-check dla Go, podsumowanie po operacji.

# ... (sekcje flag, ładowania configu, logowania i error handler bez zmian) ...
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then DRY_RUN=true; fi
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/backup_restore.config" || { echo "Błąd: Nie można załadować pliku konfiguracyjnego."; exit 1; }
COLOR_RESET='\033[0m'; COLOR_GREEN='\033[0;32m'; COLOR_RED='\033[0;31m'; COLOR_YELLOW='\033[0;33m'; COLOR_BLUE='\033[0;34m'
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1${COLOR_RESET}"; }
log_info() { log "${COLOR_BLUE}$1"; }; log_success() { log "${COLOR_GREEN}✅ $1"; }; log_error() { log "${COLOR_RED}❌ $1"; }; log_warning() { log "${COLOR_YELLOW}⚠️  $1"; }; log_dry_run() { [[ "$DRY_RUN" == "true" ]] && log_info "DRY-RUN: $1"; }
errorHandler() { local exit_code=$?; local line_num=$1; local command=$2; log_error "Wystąpił krytyczny błąd w linii $line_num: '$command' zwróciło kod $exit_code."; log_info "Rozważ użycie funkcji rollback_last_restore, aby cofnąć zmiany w plikach konfiguracyjnych."; exit $exit_code; }
trap 'errorHandler ${LINENO} "$BASH_COMMAND"' ERR
set -o pipefail

# --- ZMIENNE GLOBALNE ---
CURRENT_STEP=0
TOTAL_STEPS=0
BACKUP_DIR=""

# ... (check_dependencies, check_disk_space, validate_backup, check_gpg_key bez zmian) ...
check_dependencies() { log_info "Sprawdzanie zależności..."; local missing=0; for cmd in gh tar dpkg git wget npm pip go lsb_release dpkg-sig flatpak snap; do if ! command -v "$cmd" &> /dev/null; then log_warning "Brak polecenia: $cmd"; missing=1; fi; done; [[ $missing -eq 1 ]] && log_error "Brakują kluczowe zależności. Zainstaluj je i spróbuj ponownie." && exit 1; log_success "Zależności spełnione."; }
check_disk_space() { log_info "Sprawdzanie wolnego miejsca na dysku..."; local required_kb=1048576; local available_kb; available_kb=$(df "$HOME" | awk 'NR==2 {print $4}'); if [[ $available_kb -lt $required_kb ]]; then log_error "Za mało miejsca na dysku (dostępne: $((available_kb/1024))MB, wymagane: $((required_kb/1024))MB)."; exit 1; fi; log_success "Wystarczająca ilość miejsca na dysku."; }
validate_backup() { log_info "Walidacja integralności rozpakowanego backupu..."; if [[ ! -f "$BACKUP_DIR/apt_packages.txt" || ! -f "$BACKUP_DIR/system_info.txt" ]]; then log_error "Backup jest niekompletny."; return 1; fi; log_success "Backup wygląda na kompletny."; return 0; }
check_gpg_key() { if [[ -n "$GPG_RECIIPENT_EMAIL" ]]; then log_info "Sprawdzanie klucza GPG..."; if ! gpg --list-secret-keys "$GPG_RECIPIENT_EMAIL" &>/dev/null; then log_error "Brak klucza prywatnego dla '$GPG_RECIPIENT_EMAIL'."; return 1; fi; log_success "Klucz prywatny GPG dostępny."; fi; }
pre_flight_check() { log_info "Sprawdzenie wstępne systemu (Pre-flight check)..."; local current_distro; current_distro=$(lsb_release -si 2>/dev/null || echo "Unknown"); if [[ -f "$BACKUP_DIR/system_info.txt" ]]; then local backup_distro; backup_distro=$(grep -E "Distributor ID" "$BACKUP_DIR/system_info.txt" | cut -d: -f2 | tr -d ' '); if [[ -n "$backup_distro" && "$current_distro" != "$backup_distro" ]]; then log_warning "System docelowy ($current_distro) różni się od źródłowego ($backup_distro)."; read -r -p "Czy na pewno chcesz kontynuować? [Y/N]: " consent && [[ "${consent^^}" != "Y" ]] && exit 1; fi; fi; log_success "Sprawdzenie wstępne zakończone pomyślnie."; }
# ... (create_system_snapshot, rollback_last_restore bez zmian) ...
create_system_snapshot() { local snapshot_base_dir="$HOME/.backup_snapshots"; local snapshot_dir; snapshot_dir="$snapshot_base_dir/snapshot_$(date +%s)"; mkdir -p "$snapshot_base_dir"; log_info "Tworzenie snapshotu plików konfiguracyjnych w: $snapshot_dir"; log_dry_run "Utworzyłbym snapshot dla ${#BACKUP_PATHS[@]} ścieżek."; if [[ "$DRY_RUN" == "false" ]]; then for path in "${BACKUP_PATHS[@]}"; do if [[ -e "$path" ]]; then mkdir -p "$snapshot_dir/$(dirname "$path")"; cp -a "$path" "$snapshot_dir/$path"; fi; done; echo "$snapshot_dir" > "$snapshot_base_dir/.last_restore_snapshot"; fi; }
rollback_last_restore() { local snapshot_file="$HOME/.backup_snapshots/.last_restore_snapshot"; if [[ ! -f "$snapshot_file" ]]; then log_error "Nie znaleziono informacji o ostatnim snapshocie."; return 1; fi; local snapshot_dir; snapshot_dir=$(cat "$snapshot_file" 2>/dev/null); if [[ -d "$snapshot_dir" ]]; then log_warning "Przywracanie plików ze snapshotu: $snapshot_dir"; read -r -p "To nadpisze obecne pliki. Kontynuować? [Y/N]: " consent; if [[ "${consent^^}" == "Y" ]]; then rsync -a "$snapshot_dir/" /; log_success "Rollback plików konfiguracyjnych zakończony."; else log_error "Rollback anulowany."; fi; else log_error "Katalog snapshotu '$snapshot_dir' nie istnieje."; fi; }

# --- ULEPSZONE FUNKCJE DIAGNOSTYCZNE ---
post_restore_check() {
    log_info "Sprawdzanie poprawności przywrócenia (Health check)..."
    local failed_tools=()
    for tool in git npm pip go; do if ! command -v "$tool" &> /dev/null; then failed_tools+=("$tool"); fi; done

    # Inteligentne sprawdzanie narzędzi Go
    if command -v go &> /dev/null; then
        # Lista narzędzi Go może pochodzić z pliku logu lub z konfiguracji
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
        log_error "Następujące narzędzia nie działają lub ich brak: ${failed_tools[*]}"
        log_info "Uruchom ponownie instalację wybranych sekcji lub sprawdź logi."
        return 1
    fi
    log_success "Wszystkie kluczowe narzędzia działają poprawnie."
    return 0
}

show_restore_summary() {
    log_info "==================================="
    log_info "=== PODSUMOWANIE PRZYWRACANIA ==="
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

    echo -e "${COLOR_GREEN}📦 Pakiety APT:${COLOR_RESET}\t\t$total_apt"
    echo -e "${COLOR_GREEN}📦 Pakiety .deb:${COLOR_RESET}\t\t$total_deb"
    echo -e "${COLOR_GREEN}📦 Aplikacje Flatpak:${COLOR_RESET}\t$total_flatpak"
    echo -e "${COLOR_GREEN}📦 Aplikacje Snap:${COLOR_RESET}\t\t$total_snap"
    echo -e "${COLOR_GREEN}🔧 Repozytoria Git:${COLOR_RESET}\t$total_git"
    echo -e "${COLOR_GREEN}🐍 Pakiety Python (pip):${COLOR_RESET}\t$total_pip"
    echo -e "${COLOR_GREEN}📦 Pakiety Node.js (npm):${COLOR_RESET}\t$total_npm"
    echo -e "${COLOR_GREEN}🚀 Narzędzia Go:${COLOR_RESET}\t\t$total_go"
    echo -e "${COLOR_GREEN}📁 Pliki konfiguracyjne:${COLOR_RESET}\t${#BACKUP_PATHS[@]}"
    
    log_info "Snapshot systemu dostępny w: $(cat "$HOME/.backup_snapshots/.last_restore_snapshot" 2>/dev/null || echo "Brak")"
    log_info "W razie problemów z plikami konfiguracyjnymi, użyj: ./restore-cloud.sh --rollback"
}

# --- ULEPSZONE FUNKCJE PRZYWRACANIA ---
verify_deb_package() {
    local deb_file="$1"
    if ! dpkg --info "$deb_file" &> /dev/null; then log_error "Pakiet $deb_file jest uszkodzony lub nieprawidłowy."; return 1; fi
    if command -v dpkg-sig &> /dev/null; then
        if ! dpkg-sig --verify "$deb_file" &> /dev/null; then
            log_warning "Pakiet $deb_file nie ma prawidłowego podpisu lub nie jest podpisany."
            read -r -p "Czy nadal chcesz zainstalować? [Y/N]: " consent
            [[ "${consent^^}" != "Y" ]] && return 1
        else
            log_success "Podpis pakietu $deb_file jest prawidłowy."
        fi
    else
        log_warning "Brak 'dpkg-sig'. Pomijam weryfikację podpisu dla $deb_file."
    fi
    return 0
}

# ... (reszta funkcji i główna logika bez zmian, ale wywołają nowe wersje `verify_deb_package` i `post_restore_check`) ...
restore_apt_packages() { log_info "Przygotowanie do instalacji pakietów APT..."; mapfile -t required_packages < "$BACKUP_DIR/apt_packages.txt"; mapfile -t installed_packages < <(dpkg --get-selections | grep -v deinstall | awk '{print $1}'); local missing_packages=(); for pkg in "${required_packages[@]}"; do if ! [[ " ${installed_packages[*]} " =~ \ ${pkg}\  ]]; then missing_packages+=("$pkg"); fi; done; if [ ${#missing_packages[@]} -eq 0 ]; then log_success "Wszystkie pakiety APT są już zainstalowane."; return 0; fi; log_warning "Skrypt planuje zainstalować ${#missing_packages[@]} brakujących pakietów APT."; log_dry_run "Wykonałbym 'sudo apt-get install -y ...'"; if [[ "$DRY_RUN" == "false" ]]; then sudo apt-get update; sudo apt-get install -y "${missing_packages[@]}"; fi; log_success "Pakiety APT zainstalowane."; }
restore_deb_packages() { local log_file="$BACKUP_DIR/.log_deb_urls.txt"; if [[ ! -f "$log_file" ]]; then log_info "Plik .log_deb_urls.txt nie istnieje, pomijam."; return 0; fi; log_info "Analizowanie pakietów .deb..."; local urls_to_install=(); mapfile -t deb_urls < "$log_file"; for url in "${deb_urls[@]}"; do local pkg_name; pkg_name=$(basename "$url" | cut -d'_' -f1); if ! dpkg -s "$pkg_name" &> /dev/null; then urls_to_install+=("$url"); fi; done; if [ ${#urls_to_install[@]} -eq 0 ]; then log_success "Wszystkie pakiety .deb są już zainstalowane."; return 0; fi; log_warning "Planowane jest pobranie i instalacja .deb:"; printf " - %s\n" "${urls_to_install[@]}"; read -r -p "Kontynuować? [Y/N]: " consent && [[ "${consent^^}" != "Y" ]] && { log_error "Instalacja anulowana."; return 1; }; local TEMP_DIR; TEMP_DIR=$(mktemp -d); trap 'log_info "Czyszczenie..."; rm -rf "$TEMP_DIR"' RETURN EXIT; log_info "Pobieranie pakietów do $TEMP_DIR..."; log_dry_run "Pobrałbym ${#urls_to_install[@]} plików .deb"; if [[ "$DRY_RUN" == "false" ]]; then wget -P "$TEMP_DIR" "${urls_to_install[@]}"; sudo dpkg --configure -a; for deb_file in "$TEMP_DIR"/*.deb; do if verify_deb_package "$deb_file"; then log_info "Instalowanie $deb_file..."; sudo dpkg -i --force-confask "$deb_file"; fi; done; sudo apt-get install -f -y; fi; log_success "Pakiety .deb zainstalowane."; }
restore_git_repos() { local log_file="$BACKUP_DIR/.log_git_urls.txt"; if [[ ! -f "$log_file" ]]; then log_info "Plik .log_git_urls.txt nie istnieje, pomijam."; return 0; fi; local target_dir="$HOME/Desktop/Git_repo"; log_info "Analizowanie repozytoriów Git do sklonowania (cel: $target_dir)..."; mkdir -p "$target_dir"; local repos_to_clone=(); mapfile -t git_urls < "$log_file"; for url in "${git_urls[@]}"; do local repo_name; repo_name=$(basename "$url" .git); if [[ ! -d "$target_dir/$repo_name" ]]; then repos_to_clone+=("$url"); fi; done; if [ ${#repos_to_clone[@]} -eq 0 ]; then log_success "Wszystkie repozytoria Git są już sklonowane."; return 0; fi; log_warning "Planowane jest sklonowanie repozytoriów do '$target_dir':"; printf " - %s\n" "${repos_to_clone[@]}"; read -r -p "Kontynuować? [Y/N]: " consent && [[ "${consent^^}" != "Y" ]] && { log_error "Klonowanie anulowane."; return 1; }; log_dry_run "Sklonowałbym ${#repos_to_clone[@]} repozytoriów"; if [[ "$DRY_RUN" == "false" ]]; then for url in "${repos_to_clone[@]}"; do log_info "   -> Klonowanie: $url"; git clone "$url" "$target_dir/$(basename "$url" .git)"; done; fi; log_success "Repozytoria Git sklonowane."; }
restore_pip_packages() { local log_file="$BACKUP_DIR/.log_pip_packages.txt"; if [[ ! -f "$log_file" ]]; then log_info "Plik .log_pip_packages.txt nie istnieje, pomijam."; return 0; fi; log_info "Przygotowanie do instalacji pakietów PIP..."; log_dry_run "Zainstalowałbym pakiety z $log_file"; if [[ "$DRY_RUN" == "false" ]]; then xargs -a "$log_file" pip install --user; fi; log_success "Pakiety PIP zainstalowane."; }
restore_npm_packages() { local log_file="$BACKUP_DIR/.log_npm_global_packages.txt"; if [[ ! -f "$log_file" ]]; then log_info "Plik .log_npm_global_packages.txt nie istnieje, pomijam."; return 0; fi; log_info "Przygotowanie do instalacji globalnych pakietów NPM..."; log_dry_run "Zainstalowałbym globalnie pakiety z $log_file"; if [[ "$DRY_RUN" == "false" ]]; then xargs -a "$log_file" sudo npm install -g; fi; log_success "Globalne pakiety NPM zainstalowane."; }
restore_go_packages() { local log_file="$BACKUP_DIR/.log_go_packages.txt"; if [[ ! -f "$log_file" ]]; then log_warning "Brak pliku .log_go_packages.txt, używam listy z konfiguracji."; if [ ${#GO_TOOLS_TO_BACKUP[@]} -eq 0 ]; then log_info "Brak narzędzi Go w konfiguracji. Pomijam."; return 0; fi; log_dry_run "Zainstalowałbym narzędzia Go z konfiguracji."; if [[ "$DRY_RUN" == "false" ]]; then for tool in "${GO_TOOLS_TO_BACKUP[@]}"; do go install "$tool"; done; fi; else log_info "Przygotowanie do instalacji narzędzi Go..."; log_dry_run "Zainstalowałbym narzędzia Go z $log_file"; if [[ "$DRY_RUN" == "false" ]]; then xargs -a "$log_file" -n 1 go install; fi; fi; log_success "Narzędzia Go zainstalowane."; }
restore_flatpak_apps() { local log_file="$BACKUP_DIR/flatpak_apps.txt"; if [[ ! -f "$log_file" ]]; then log_info "Plik flatpak_apps.txt nie istnieje, pomijam."; return 0; fi; log_info "Przygotowanie do instalacji aplikacji Flatpak..."; log_dry_run "Zainstalowałbym aplikacje z $log_file"; if [[ "$DRY_RUN" == "false" ]] && command -v flatpak &> /dev/null; then xargs -a "$log_file" -r flatpak install -y; fi; log_success "Aplikacje Flatpak zainstalowane."; }
restore_snap_apps() { local log_file="$BACKUP_DIR/snap_apps.txt"; if [[ ! -f "$log_file" ]]; then log_info "Plik snap_apps.txt nie istnieje, pomijam."; return 0; fi; log_info "Przygotowanie do instalacji aplikacji Snap..."; log_dry_run "Zainstalowałbym aplikacje z $log_file"; if [[ "$DRY_RUN" == "false" ]] && command -v snap &> /dev/null; then xargs -a "$log_file" -r sudo snap install; fi; log_success "Aplikacje Snap zainstalowane."; }
restore_config_files() { ((CURRENT_STEP++)); log_info "Krok ${CURRENT_STEP}/${TOTAL_STEPS}: PRZYWRACANIE PLIKÓW KONFIGURACYJNYCH"; create_system_snapshot; for item_path in "${BACKUP_PATHS[@]}"; do local src_path_in_backup; src_path_in_backup="$BACKUP_DIR/$(basename "$item_path")"; if [ -e "$src_path_in_backup" ]; then log_info "   -> Przywracanie: $item_path"; log_dry_run "Przywróciłbym $src_path_in_backup do $item_path"; if [[ "$DRY_RUN" == "false" ]]; then if [ -e "$item_path" ]; then mv "$item_path" "${item_path}.before_restore_$(date +%s)"; fi; sudo cp -a "$src_path_in_backup" "$item_path"; fi; fi; done; }
show_restore_menu() { log_info "Wybierz sekcje do przywrócenia:"; PS3="Twój wybór: "; options=("Wszystko (zalecane)" "Tylko pliki konfiguracyjne" "Tylko pakiety systemowe (APT, DEB, Flatpak, Snap)" "Tylko środowisko deweloperskie (Git, Pip, Npm, Go)" "Anuluj"); select opt in "${options[@]}"; do case $opt in "Wszystko (zalecane)") TOTAL_STEPS=4; full_restore; break ;; "Tylko pliki konfiguracyjne") TOTAL_STEPS=1; restore_config_files; break ;; "Tylko pakiety systemowe (APT, DEB, Flatpak, Snap)") TOTAL_STEPS=1; ((CURRENT_STEP++)); log_info "Krok ${CURRENT_STEP}/${TOTAL_STEPS}: INSTALACJA PAKIETÓW SYSTEMOWYCH"; restore_apt_packages; restore_deb_packages; restore_flatpak_apps; restore_snap_apps; break ;; "Tylko środowisko deweloperskie (Git, Pip, Npm, Go)") TOTAL_STEPS=1; ((CURRENT_STEP++)); log_info "Krok ${CURRENT_STEP}/${TOTAL_STEPS}: PRZYWRACANIE ŚRODOWISKA DEWELOPERSKIEGO"; restore_git_repos; restore_pip_packages; restore_npm_packages; restore_go_packages; break ;; "Anuluj") log_info "Operacja anulowana."; exit 0 ;; *) log_warning "Nieprawidłowy wybór.";; esac; done; }
full_restore() { restore_config_files; ((CURRENT_STEP++)); log_info "Krok ${CURRENT_STEP}/${TOTAL_STEPS}: INSTALACJA PAKIETÓW SYSTEMOWYCH"; restore_apt_packages; restore_deb_packages; restore_flatpak_apps; restore_snap_apps; ((CURRENT_STEP++)); log_info "Krok ${CURRENT_STEP}/${TOTAL_STEPS}: PRZYWRACANIE ŚRODOWISKA DEWELOPERSKIEGO"; restore_git_repos; restore_pip_packages; restore_npm_packages; restore_go_packages; }

main() {
    if [[ "$1" == "--rollback" ]]; then rollback_last_restore; exit 0; fi
    if [[ "$DRY_RUN" == "true" ]]; then log_warning "Uruchomiono w trybie --dry-run."; fi
    check_dependencies; check_disk_space
    log_info "Pobieranie listy dostępnych backupów..."; local TAGS; TAGS=$(gh release list --repo "$GH_REPO" --limit 10 --json tagName -q '.[].tagName'); if [ -z "$TAGS" ]; then log_error "Nie znaleziono żadnych backupów."; exit 1; fi
    log_info "Wybierz backup do przywrócenia:"; select SELECTED_TAG in $TAGS; do if [ -n "$SELECTED_TAG" ]; then log_info "Wybrano: $SELECTED_TAG"; break; else log_warning "Nieprawidłowy wybór."; fi; done
    log_info "Pobieranie archiwum ($SELECTED_TAG)..."; log_dry_run "Pobrałbym archiwum"; if [[ "$DRY_RUN" == "false" ]]; then gh release download "$SELECTED_TAG" --repo "$GH_REPO" --pattern "backup_*.tar.gz*" --clobber; fi
    local DOWNLOADED_ARCHIVE; DOWNLOADED_ARCHIVE=$(find . -maxdepth 1 -name "backup_*.tar.gz*" -print -quit); if [[ -z "$DOWNLOADED_ARCHIVE" && "$DRY_RUN" == "false" ]]; then log_error "Nie udało się pobrać archiwum."; exit 1; fi
    if [[ "$DOWNLOADED_ARCHIVE" == *.gpg ]]; then check_gpg_key || exit 1; log_dry_run "Odszyfrowałbym i rozpakowałbym $DOWNLOADED_ARCHIVE"; [[ "$DRY_RUN" == "false" ]] && gpg --decrypt "$DOWNLOADED_ARCHIVE" | sudo tar --numeric-owner -xzf -; else log_dry_run "Rozpakowałbym $DOWNLOADED_ARCHIVE"; [[ "$DRY_RUN" == "false" ]] && sudo tar --numeric-owner -xzf "$DOWNLOADED_ARCHIVE"; fi
    BACKUP_DIR=$(find . -maxdepth 1 -type d -name "backup_*" -print -quit); if [ -z "$BACKUP_DIR" ]; then log_error "Nie znaleziono rozpakowanego folderu."; exit 1; fi
    validate_backup || exit 1; pre_flight_check
    show_restore_menu
    ((CURRENT_STEP++)); log_info "Krok ${CURRENT_STEP}/${TOTAL_STEPS}: SPRAWDZENIE KOŃCOWE"; post_restore_check
    show_restore_summary # NOWE: Wywołanie podsumowania
    log_success "Operacja przywracania zakończona pomyślnie."
}
main "$@"
