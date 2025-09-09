# 📦 github-release-dotfiles-backup

![Project Banner](assets/banner.svg)

[![ShellCheck](https://img.shields.io/badge/shellcheck-passed-brightgreen)](https://www.shellcheck.net) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

> 🛡️ A simple and secure script for backing up configuration files (dotfiles) to a private GitHub Releases repository, with optional GPG encryption.

## Why this project?

Simple, auditable shell scripts to package and push local backups as GitHub Releases. Useful for:

-   Quick backups of configuration files and package lists.
-   Securely sharing configurations between your devices (with GPG encryption).
-   Integration with local automation (`cron` / `systemd`).

## Features

-   🔁 Creates a timestamped `tar.gz` archive containing selected files and directories.
-   🔐 Optional GPG encryption for the archive.
-   📤 Uploads the archive to GitHub Releases using the `gh` CLI.
-   📥 Restores a backup from an interactive list of available releases in the repository.
-   🧪 A `--dry-run` option to simulate execution without making any changes.
-   📝 Optional logging of all operations to a file, configured in `backup_restore.config`.

---

## ⚡ Quickstart

<details>
<summary>Show quickstart commands</summary>

```bash
# Example for Debian/Ubuntu
sudo apt update && sudo apt install -y gh jq gpg pv tar coreutils

# Authenticate with the GitHub CLI
gh auth login

# Copy and edit the configuration file
cp backup_restore.config.example backup_restore.config
# Change GH_REPO and BACKUP_PATHS in the backup_restore.config file

# Verify the setup with a dry-run
./backup-cloud.sh --dry-run

# Create a real backup
./backup-cloud.sh
</details>

Configuration
Copy backup_restore.config.example to backup_restore.config and customize it to your needs.

Ini, TOML

# GH_REPO: owner/repo (must be private to maintain confidentiality)
GH_REPO="your-user/backup-dotfiles"

# Path to the log file. An empty value ("") disables logging.
LOG_FILE="$HOME/backup_restore.log"

# Optional GPG encryption: recipient's email or key ID. An empty value disables encryption.
GPG_RECIPIENT_EMAIL="your.public.key@example.com"

# Paths to files/directories to be included in the backup
BACKUP_PATHS=(
    "$HOME/.config"
    "$HOME/.zshrc"
    "$HOME/.secrets"
)
Tip: The backup_restore.config file should be kept out of version control (e.g., in .gitignore) if it contains sensitive information. Only commit backup_restore.config.example to the repository.

Usage & Examples
Creating a Backup
Default run (creates archive, optionally encrypts, pushes to GitHub):

Bash

./backup-cloud.sh
Run in simulation mode (no files are created, no data is sent):

Bash

./backup-cloud.sh --dry-run
Restoring a Backup
Run in interactive mode (will display a list of available backups to choose from):

Bash

./restore-cloud.sh
Listing available releases (using gh):
Bash

gh release list --repo "$GH_REPO"
GPG Encryption Workflow
Generate keys locally (if you don't have them):
gpg --full-generate-key

Export your public key and import it on the machine that will be performing the backup:
gpg --armor --export you@example.com > pubkey.asc

In the backup_restore.config file, set GPG_RECIPIENT_EMAIL to the key's email or ID.

The script will automatically encrypt the archive. To decrypt it manually:
gpg --decrypt backup-...tar.gz.gpg > backup-...tar.gz

Important: Always keep your private key in a safe, local place. Never commit it to this repository.

Archive Naming and Verification
Archive files are named according to the following scheme:
backup-YEAR-MONTH-DAY_HOURMINUTESECOND.tar.gz
or, if encrypted:
backup-YEAR-MONTH-DAY_HOURMINUTESECOND.tar.gz.gpg

Before starting the restore process, the restore-cloud.sh script performs a basic completeness check by verifying the presence of key files (e.g., system_info.txt) inside the unpacked archive.

Security
Use gh auth login for interactive authentication. If you must use a token, grant it the minimum required permissions (repo for private repositories).

Ensure the GitHub repository is set to private if the backup contains sensitive data.

Consider using GPG encryption as an additional layer of protection.

Troubleshooting
gh authentication error: Run gh auth status and, if necessary, gh auth login.

GPG errors: Ensure the recipient's public key is available on the backup machine and the private key is available on the restore machine.

Problems uploading large archives: GitHub has limits on release asset sizes. Consider splitting the archive or using a different storage provider.

License
This project is licensed under the MIT License - see the LICENSE file for details.
