# github-release-dotfiles-backup
GitHub Release Dotfiles BackupZestaw skryptów powłoki Bash do tworzenia i przywracania kopii zapasowych konfiguracji systemu (dotfiles) przy użyciu prywatnego repozytorium GitHub i mechanizmu Releases jako bezpiecznego magazynu danych.OpisProjekt ten oferuje dwa główne skrypty: backup-cloud.sh i restore-cloud.sh. Umożliwiają one zautomatyzowane tworzenie zaszyfrowanych (GPG) archiwów z wybranymi plikami konfiguracyjnymi, listami pakietów i informacjami o systemie, a następnie wysyłanie ich jako "Release" do prywatnego repozytorium na GitHubie. Dzięki temu zyskujesz wersjonowany, bezpieczny i darmowy backup swojego środowiska pracy, który możesz łatwo przywrócić na nowej maszynie.Kluczowe funkcjeBezpieczny magazyn: Wykorzystuje prywatne repozytorium GitHub i jego Releases do przechowywania backupów.Szyfrowanie end-to-end: Opcjonalne szyfrowanie archiwów za pomocą GPG przed wysłaniem.Automatyzacja: Proste w użyciu skrypty do tworzenia i przywracania kopii zapasowych.Elastyczna konfiguracja: Łatwe zarządzanie ścieżkami do backupu w dedykowanym pliku konfiguracyjnym.Inteligentne zarządzanie: Automatyczne czyszczenie starych backupów z GitHuba.Bezpieczeństwo użycia: Tryb --dry-run pozwala na symulację działania skryptów bez wprowadzania zmian.Solidna obsługa błędów: Profesjonalne przechwytywanie błędów i czytelne logowanie.Instalacja i KonfiguracjaWymagania wstępneUpewnij się, że masz zainstalowane następujące narzędzia:gh: Oficjalny klient wiersza poleceń GitHuba.gpg: Do szyfrowania i deszyfrowania backupów.tar, gzip: Standardowe narzędzia do archiwizacji.pv (opcjonalnie): Do wyświetlania paska postępu podczas archiwizacji.# Na systemach bazujących na Debian/Ubuntu
sudo apt update
sudo apt install github-cli gnupg2 tar gzip pv
Po instalacji gh, zaloguj się na swoje konto:gh auth login
Kroki instalacjiSklonuj repozytorium:git clone [https://github.com/TWOJA_NAZWA_UŻYTKOWNIKA/TWOJA_NAZWA_REPOZYTORIUM.git](https://github.com/TWOJA_NAZWA_UŻYTKOWNIKA/TWOJA_NAZWA_REPOZYTORIUM.git)
cd TWOJA_NAZWA_REPOZYTORIUM
Nadaj uprawnienia do wykonywania skryptów:chmod +x backup-cloud.sh restore-cloud.sh
Skonfiguruj projekt:Otwórz plik backup_restore.config i dostosuj go do swoich potrzeb.GH_REPO: Ustaw nazwę swojego prywatnego repozytorium na GitHubie, które będzie służyć jako magazyn.GH_REPO="user/my-private-backup-repo"
GPG_RECIPIENT_EMAIL: Podaj adres e-mail powiązany z Twoim kluczem publicznym GPG, aby włączyć szyfrowanie. Jeśli zostawisz puste, szyfrowanie będzie wyłączone.# Przykład z włączonym szyfrowaniem
GPG_RECIPIENT_EMAIL="your.email@example.com"

# Przykład z wyłączonym szyfrowaniem
GPG_RECIPIENT_EMAIL=""
BACKUP_PATHS: Zdefiniuj listę plików i katalogów, które mają być dołączone do kopii zapasowej. Używaj zmiennej $HOME, aby ścieżki były uniwersalne.BACKUP_PATHS=(
    "$HOME/.zshrc"
    "$HOME/.config/git"
    "$HOME/.ssh/config"
)
UżycieTworzenie kopii zapasowejAby utworzyć nową kopię zapasową i wysłać ją na GitHub, uruchom skrypt:./backup-cloud.sh
Aby zasymulować proces bez tworzenia i wysyłania plików:./backup-cloud.sh --dry-run
Przywracanie kopii zapasowejAby przywrócić konfigurację z istniejącej kopii zapasowej:./restore-cloud.sh
Skrypt wyświetli listę dostępnych backupów (release'ów) i poprosi o wybór jednego z nich.Aby zasymulować proces przywracania:./restore-cloud.sh --dry-run
LicencjaProjekt jest udostępniany na licencji MIT. Zobacz plik LICENSE, aby uzyskać więcej informacji.
