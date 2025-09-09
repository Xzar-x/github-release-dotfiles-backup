Dotfiles Backup & Restore Scripts
Zestaw profesjonalnych skryptów Bash do automatyzacji procesu tworzenia kopii zapasowych i przywracania plików konfiguracyjnych (dotfiles), list pakietów i ustawień systemowych. Skrypty wykorzystują prywatne repozytorium GitHub jako bezpieczne miejsce do przechowywania zaszyfrowanych archiwów w formie GitHub Releases.

Główne Funkcje
Backup w Chmurze: Automatyczne tworzenie archiwum .tar.gz i wysyłanie go jako nowy Release do Twojego prywatnego repozytorium GitHub.

Szyfrowanie GPG: Opcjonalne, w pełni zautomatyzowane szyfrowanie kopii zapasowych przy użyciu klucza publicznego GPG dla maksymalnego bezpieczeństwa.

Interaktywne Przywracanie: Skrypt restore-cloud.sh pobiera listę dostępnych backupów i pozwala wybrać, który z nich chcesz przywrócić.

Profesjonalna Obsługa Błędów: Użycie trap i set -o pipefail zapewnia, że skrypt zatrzyma się natychmiast po wystąpieniu błędu, informując o problematycznej komendzie.

Tryb Testowy (--dry-run): Uruchom skrypty z flagą --dry-run, aby zasymulować cały proces bez wprowadzania jakichkolwiek zmian w systemie.

Elastyczna Konfiguracja: Wszystkie ścieżki, nazwa repozytorium i ustawienia GPG są zarządzane w jednym pliku backup_restore.config.

Walidacja i Bezpieczeństwo: Skrypty sprawdzają zależności, dostępną przestrzeń dyskową oraz weryfikują, czy repozytorium jest prywatne.

Wymagania
bash

gh - Oficjalny klient wiersza poleceń GitHub.

jq - Do parsowania danych JSON z gh.

gpg (opcjonalnie) - Wymagane tylko jeśli chcesz korzystać z szyfrowania.

pv (opcjonalnie) - Do wyświetlania paska postępu podczas archiwizacji.

Instalacja i Konfiguracja
Utwórz Prywatne Repozytorium na GitHub
Stwórz nowe, prywatne repozytorium na swoim koncie GitHub. Będzie ono służyło jako magazyn dla Twoich kopii zapasowych.

Sklonuj Repozytorium

git clone [https://github.com/TWOJA_NAZWA/TWOJE_REPO.git](https://github.com/TWOJA_NAZWA/TWOJE_REPO.git)
cd TWOJE_REPO

Nadaj Uprawnienia Wykonywania

chmod +x backup-cloud.sh
chmod +x restore-cloud.sh

** skonfiguruj backup_restore.config**
Otwórz plik backup_restore.config i dostosuj go do swoich potrzeb:

GH_REPO: Ustaw nazwę swojego prywatnego repozytorium (np. "moj-user/dotfiles-backup").

GPG_RECIPIENT_EMAIL: Podaj e-mail powiązany z Twoim kluczem publicznym GPG, aby włączyć szyfrowanie. Jeśli zostawisz puste (""), szyfrowanie będzie wyłączone.

BACKUP_PATHS: Zaktualizuj listę plików i katalogów, które chcesz dołączyć do kopii zapasowej. Używaj zmiennej $HOME, aby ścieżki były uniwersalne.

Użycie
Tworzenie Kopii Zapasowej
Aby utworzyć nową kopię zapasową, uruchom skrypt backup-cloud.sh:

./backup-cloud.sh

Skrypt spakuje zdefiniowane pliki, zaszyfruje je (jeśli skonfigurowano) i wyśle do Twojego repozytorium na GitHub jako nowy Release.

Przywracanie z Kopii Zapasowej
Aby przywrócić system z istniejącej kopii zapasowej, uruchom skrypt restore-cloud.sh:

./restore-cloud.sh

Skrypt połączy się z GitHub, wyświetli listę 10 ostatnich backupów, a Ty będziesz mógł wybrać, który z nich pobrać i przywrócić.

Tryb Testowy
Aby zobaczyć, co zrobiłyby skrypty, bez dokonywania żadnych zmian, użyj flagi --dry-run:

./backup-cloud.sh --dry-run
./restore-cloud.sh --dry-run

Licencja
Ten projekt jest objęty licencją MIT.
