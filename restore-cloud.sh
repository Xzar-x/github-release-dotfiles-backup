#!/bin/bash
# Wersja 5.2: Profesjonalizacja, tryb dry-run i obsługa błędów.
# Zmiany:
# - USUNIĘTO: Błąd składniowy (dodatkowy nawias '}' na końcu pliku).
# + DODANO: Profesjonalną obsługę błędów z 'trap', spójną z backup-cloud.sh.
# - Dodano tryb --dry-run do symulacji.
# - Lepsza walidacja backupu (zbiorcze błędy).
# - Dodano sprawdzanie wolnego miejsca na dysku.
# - Dodano weryfikację dostępności klucza prywatnego GPG przed deszyfrowaniem.

# --- ANALIZA FLAG ---
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# --- ŁADOWANIE KONFIGURACJI ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/backup_restore.config" || { echo "Błąd: Nie można załadować pliku konfiguracyjnego."; exit 1; }
# ---

# --- Kolory i logowanie ---
COLOR_RESET='\033[0m'; COLOR_GREEN='\033[0;32m'; COLOR_RED='\033[0;31m'; COLOR_YELLOW='\033[0;33m'; COLOR_BLUE='\033[0;34m'
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1${COLOR_RESET}"; }
log_info() { log "${COLOR_BLUE}$1"; }
log_success() { log "${COLOR_GREEN}✅ $1"; }
log_error() { log "${COLOR_RED}❌ $1"; }
log_warning() { log "${COLOR_YELLOW}⚠️  $1"; }
log_dry_run() { [[ "$DRY_RUN" == "true" ]] && log_info "DRY-RUN: $1"; }

# --- PROFESJONALNA OBSŁUGA BŁĘDÓW ---
errorHandler() {
    local exit_code=$?
    local line_num=$1
    local command=$2
    log_error "Wystąpił krytyczny błąd w linii $line_num: polecenie '$command' zwróciło kod błędu $exit_code."
    exit $exit_code
}
trap 'errorHandler ${LINENO} "$BASH_COMMAND"' ERR
set -o pipefail
# ---

# --- FUNKCJE POMOCNICZE ---
check_dependencies() {
    log_info "Sprawdzanie zależności (gh, tar)..."
    local missing=0
    for cmd in gh tar; do
        if ! command -v "$cmd" &> /dev/null; then log_error "Brak polecenia: $cmd"; missing=1; fi
    done
    [[ $missing -eq 1 ]] && exit 1
    log_success "Zależności spełnione."
}

check_disk_space() {
    log_info "Sprawdzanie wolnego miejsca na dysku..."
    local required_kb=1048576 # 1GB
    local available_kb
    available_kb=$(df "$HOME" | awk 'NR==2 {print $4}')
    if [[ $available_kb -lt $required_kb ]]; then
        log_error "Za mało miejsca na dysku (dostępne: $((available_kb/1024))MB, wymagane: $((required_kb/1024))MB)."
        exit 1
    fi
    log_success "Wystarczająca ilość miejsca na dysku."
}

validate_backup() {
    log_info "Walidacja integralności rozpakowanego backupu..."
    local errors=()
    [[ ! -f "$BACKUP_DIR/apt_packages.txt" ]] && errors+=("Brak pliku apt_packages.txt")
    [[ ! -f "$BACKUP_DIR/system_info.txt" ]] && errors+=("Brak pliku system_info.txt")
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Backup jest niekompletny. Błędy: ${errors[*]}"
        return 1
    fi
    log_success "Backup wygląda na kompletny."
    return 0
}

check_gpg_key() {
    if [[ -n "$GPG_RECIPIENT_EMAIL" ]]; then
        log_info "Sprawdzanie dostępności klucza prywatnego GPG..."
        if ! gpg --list-secret-keys "$GPG_RECIPIENT_EMAIL" &>/dev/null; then
            log_error "Brak klucza prywatnego dla '$GPG_RECIPIENT_EMAIL'. Nie można odszyfrować backupu."
            return 1
        fi
        log_success "Klucz prywatny GPG jest dostępny."
    fi
}

# --- GŁÓWNA LOGIKA ---
main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Uruchomiono w trybie --dry-run. Żadne zmiany nie zostaną wprowadzone."
    fi

    check_dependencies
    check_disk_space

    # --- Wybór backupu do przywrócenia ---
    log_info "Pobieranie listy dostępnych backupów..."
    TAGS=$(gh release list --repo "$GH_REPO" --limit 10 --json tagName -q '.[].tagName')
    if [ -z "$TAGS" ]; then
        log_error "Nie znaleziono żadnych backupów (release'ów) w repozytorium $GH_REPO."
        exit 1
    fi

    log_info "Wybierz backup do przywrócenia:"
    select SELECTED_TAG in $TAGS; do
        if [ -n "$SELECTED_TAG" ]; then
            log_info "Wybrano: $SELECTED_TAG"
            break
        else
            log_warning "Nieprawidłowy wybór. Spróbuj ponownie."
        fi
    done
    
    # --- Pobieranie i rozpakowywanie ---
    DOWNLOADED_ARCHIVE=$(ls -t backup_*.tar.gz* 2>/dev/null | head -n 1) # symulacja dla dry-run
    log_info "Pobieranie archiwum ($SELECTED_TAG)..."
    log_dry_run "Pobrałbym archiwum dla tagu $SELECTED_TAG"
    [[ "$DRY_RUN" == "false" ]] && gh release download "$SELECTED_TAG" --repo "$GH_REPO" --pattern "backup_*.tar.gz*" --clobber && DOWNLOADED_ARCHIVE=$(ls -t backup_*.tar.gz* 2>/dev/null | head -n 1)

    if [[ "$DOWNLOADED_ARCHIVE" == *.gpg ]]; then
        check_gpg_key || exit 1
        log_dry_run "Odszyfrowałbym i rozpakowałbym $DOWNLOADED_ARCHIVE"
        [[ "$DRY_RUN" == "false" ]] && gpg --decrypt "$DOWNLOADED_ARCHIVE" | sudo tar --numeric-owner -xzf -
    else
        log_dry_run "Rozpakowałbym $DOWNLOADED_ARCHIVE"
        [[ "$DRY_RUN" == "false" ]] && sudo tar --numeric-owner -xzf "$DOWNLOADED_ARCHIVE"
    fi
    
    BACKUP_DIR=$(ls -d backup_*/ 2>/dev/null | head -n 1)
    if [ -z "$BACKUP_DIR" ]; then log_error "Nie znaleziono rozpakowanego folderu." && exit 1; fi
    
    validate_backup || exit 1

    # --- Dialog z użytkownikiem ---
    # ... (można dodać logikę pytającą użytkownika o kontynuację) ...
    
    # --- SEKCJA 1: INSTALACJA BRAKUJĄCEGO OPROGRAMOWANIA ---
    log_info "SEKCJA 1: INSTALACJA BRAKUJĄCEGO OPROGRAMOWANIA"
    # ... (logika instalacji oprogramowania, np. apt, pip, go) ...
    
    # --- SEKCJA 2: PRZYWRACANIE PLIKÓW KONFIGURACYJNYCH ---
    log_info "SEKCJA 2: PRZYWRACANIE PLIKÓW KONFIGURACYJNYCH"
    for item_path in "${BACKUP_PATHS[@]}"; do
        src_path_basename=$(basename "$item_path")
        src_path_in_backup="$BACKUP_DIR/$src_path_basename"

        if [ -e "$src_path_in_backup" ]; then
            log_info "   -> Przywracanie: $item_path"
            log_dry_run "Przywróciłbym $src_path_in_backup do $item_path"
            if [[ "$DRY_RUN" == "false" ]]; then
                # Tworzenie kopii zapasowej istniejącego pliku przed nadpisaniem
                if [ -e "$item_path" ]; then
                    mv "$item_path" "${item_path}.before_restore_$(date +%s)"
                fi
                # Kopiowanie z zachowaniem praw właściciela
                sudo cp -a "$src_path_in_backup" "$item_path"
            fi
        else
            log_warning "Nie znaleziono źródła w backupie dla '$item_path'. Pomijam."
        fi
    done

    log_success "Operacja przywracania zakończona."
}

main
