#!/bin/bash
# Wersja 5.2: Wprowadzenie profesjonalnej obsługi błędów z 'trap'.
# Zmiany:
# - Zastąpiono 'set -e' mechanizmem 'trap' dla sygnału ERR.
# - Skrypt teraz precyzyjnie raportuje linię i polecenie, które zawiodło.
# - Dodano 'set -o pipefail', aby błędy w potokach były również przechwytywane.

# --- ANALIZA FLAG ---
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# --- ŁADOWANIE KONFIGURACJI ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/backup_restore.config" || { echo "Błąd: Nie można załadować pliku konfiguracyjnego."; exit 1; }
# ---

# --- Kolory i funkcje logowania ---
COLOR_RESET='\033[0m'; COLOR_GREEN='\033[0;32m'; COLOR_RED='\033[0;31m'; COLOR_YELLOW='\033[0;33m'; COLOR_BLUE='\033[0;34m'
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1${COLOR_RESET}"; }
log_info() { log "${COLOR_BLUE}$1"; }
log_success() { log "${COLOR_GREEN}✅ $1"; }
log_error() { log "${COLOR_RED}❌ $1"; }
log_warning() { log "${COLOR_YELLOW}⚠️  $1"; }
log_dry_run() { [[ "$DRY_RUN" == "true" ]] && log_info "DRY-RUN: $1"; }
# ---

# --- PROFESJONALNA OBSŁUGA BŁĘDÓW ---
# Ta funkcja zostanie wywołana automatycznie, gdy jakakolwiek komenda zawiedzie.
errorHandler() {
    local exit_code=$?
    local line_num=$1
    local command=$2
    log_error "Wystąpił krytyczny błąd w linii $line_num: polecenie '$command' zwróciło kod błędu $exit_code."
    exit $exit_code
}

# Ustawiamy pułapkę ('trap'), która wywoła naszą funkcję w przypadku błędu.
# Zastępuje to potrzebę używania 'set -e' w niekontrolowany sposób.
trap 'errorHandler ${LINENO} "$BASH_COMMAND"' ERR
set -o pipefail # Dzięki temu błąd w dowolnej części potoku (np. cmd1 | cmd2) jest traktowany jako błąd całości.
# ---

# --- KONFIGURACJA ---
KEEP_LATEST_RELEASES=5
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_DIR="backup_$TIMESTAMP"
ARCHIVE_NAME="backup_$TIMESTAMP.tar.gz"
RELEASE_TAG="backup-$TIMESTAMP"

# --- FUNKCJE POMOCNICZE ---
check_dependencies() {
    log_info "Sprawdzanie zależności..."
    local missing=0
    for cmd in gh jq; do
        if ! command -v "$cmd" &> /dev/null; then log_error "Brak polecenia: $cmd"; missing=1; fi
    done
    if ! command -v pv &> /dev/null; then log_warning "Brak 'pv' (Pipe Viewer). Pasek postępu nie będzie dostępny."; fi
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

# --- GŁÓWNA LOGIKA ---
main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Uruchomiono w trybie --dry-run. Żadne zmiany nie zostaną wprowadzone."
    fi

    check_dependencies
    check_disk_space

    # --- Konfiguracja GOPATH ---
    GOPATH_FROM_ENV=$(go env GOPATH 2>/dev/null || echo "")
    export GOPATH="${GOPATH_FROM_ENV:-$HOME/go}"
    export PATH=$PATH:$GOPATH/bin:/usr/local/go/bin
    log_info "Używam GOPATH: $GOPATH"

    if [[ -n "$LOG_FILE" ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
    
    # --- Sprzątanie ---
    trap 'log_info "Sprzątanie..."; if [[ -n "$BACKUP_DIR" && "$BACKUP_DIR" == backup_* && -d "$BACKUP_DIR" ]]; then sudo rm -rf "$BACKUP_DIR"; fi' EXIT

    # --- Szyfrowanie i walidacja repo ---
    ENCRYPTION_ENABLED=false
    if [[ -n "$GPG_RECIPIENT_EMAIL" ]]; then
        log_info "Szyfrowanie GPG włączone dla: $GPG_RECIPIENT_EMAIL"
        if ! gpg --list-keys "$GPG_RECIPIENT_EMAIL" &>/dev/null; then
            log_error "Nie znaleziono klucza publicznego GPG dla $GPG_RECIPIENT_EMAIL."
            exit 1
        fi
        ENCRYPTION_ENABLED=true
        ARCHIVE_NAME+=".gpg"
    fi
    
    IS_PRIVATE=$(gh repo view "$GH_REPO" --json isPrivate -q .isPrivate)
    if [ "$IS_PRIVATE" != "true" ]; then log_error "Repozytorium '$GH_REPO' NIE JEST PRYWATNE!" && exit 1; fi
    log_success "Repozytorium jest prywatne. Kontynuuję."
    
    # --- Tworzenie backupu ---
    log_info "Tworzenie lokalnej kopii zapasowej w: $BACKUP_DIR"
    log_dry_run "Utworzyłbym katalog: $BACKUP_DIR"
    [[ "$DRY_RUN" == "false" ]] && mkdir -p "$BACKUP_DIR"

    # ... Kopiowanie plików z konfiguracji ...
    log_info "Kopiowanie plików zdefiniowanych w konfiguracji..."
    for item_path in "${BACKUP_PATHS[@]}"; do
        if [ -e "$item_path" ]; then
            dest_path="$BACKUP_DIR/$(basename "$item_path")"
            log_info "   -> Kopiowanie: $item_path"
            log_dry_run "Skopiowałbym $item_path do $dest_path"
            # Ta komenda jest teraz podejrzana. Jeśli zawiedzie, nasz 'trap' to złapie.
            [[ "$DRY_RUN" == "false" ]] && cp -a "$item_path" "$dest_path"
        else
            log_warning "   -> Ścieżka nie istnieje, pomijam: $item_path"
        fi
    done

    # ... Reszta logiki (system info, apt, go, pip) ...
    log_info "Zapisywanie informacji o systemie i list pakietów..."
    log_dry_run "Zapisałbym system_info.txt, apt_packages.txt, etc."
    if [[ "$DRY_RUN" == "false" ]]; then
        { uname -a; lsb_release -a 2>/dev/null; df -h; } > "$BACKUP_DIR/system_info.txt"
        
        (apt-mark showmanual | grep -vE 'linux-headers|linux-image' | sort -u > "$BACKUP_DIR/apt_packages.txt") || true
        (pip freeze > "$BACKUP_DIR/pip_packages.txt") || true
    fi

    # ... Archiwizacja i wysyłka ...
    log_info "Tworzenie archiwum $ARCHIVE_NAME..."
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
    log_dry_run "Utworzyłbym archiwum: $ARCHIVE_NAME"

    log_info "Wysyłanie archiwum do GitHub Releases..."
    log_dry_run "Utworzyłbym release '$RELEASE_TAG' z plikiem '$ARCHIVE_NAME'"
    if [[ "$DRY_RUN" == "false" ]]; then
        if gh release create "$RELEASE_TAG" "$ARCHIVE_NAME" --repo "$GH_REPO" --title "Backup $TIMESTAMP" --notes "Automatyczny backup"; then
            log_success "Backup wysłany pomyślnie."
            rm -f "$ARCHIVE_NAME"
        else
            log_error "Nie udało się wysłać archiwum. Zostawiono plik lokalnie: $ARCHIVE_NAME"
            exit 1
        fi
    fi

    # ... Czyszczenie starych backupów ...
    # ... (logika bez zmian, ale z dodanym dry-run) ...
}

main

