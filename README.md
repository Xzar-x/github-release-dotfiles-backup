# 💾 Dotfiles Backup & Restore Scripts

Professional **Bash scripts** to automate the backup and restoration of your configuration files (dotfiles), system settings, and package lists.  
Backups are securely stored as **GitHub Releases** in a **private repository**, optionally encrypted with GPG.

---

## ⚡ Key Features

- **☁️ Cloud Backup**: Automatically creates a `.tar.gz` archive and uploads it as a new Release to your private GitHub repository.  
- **🔒 GPG Encryption**: Optional fully-automated encryption using your public GPG key for maximum security.  
- **🛠️ Interactive Restore**: `restore-cloud.sh` fetches a list of available backups, allowing you to choose which one to restore.  
- **⚠️ Robust Error Handling**: Uses `trap` and `set -o pipefail` to stop immediately on errors, showing the problematic command.  
- **🧪 Dry-Run Mode**: Simulate the backup or restore process without making any changes using `--dry-run`.  
- **⚙️ Flexible Configuration**: All paths, repository names, and GPG settings are managed in a single `backup_restore.config` file.  
- **✅ Validation & Safety Checks**: Scripts verify dependencies, disk space, and ensure the repository is private.

---

## 📝 Requirements

- `bash`
- `gh` – GitHub CLI
- `jq` – for parsing JSON from `gh`
- `gpg` (optional) – required only if you want encryption
- `pv` (optional) – for progress bar during archiving

---

## 🚀 Installation & Setup

### 1. Create a Private GitHub Repository
Create a new **private repository** on GitHub to store your backups.

### 2. Clone the Repository
```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
3. Make Scripts Executable
bash
Copy code
chmod +x backup-cloud.sh
chmod +x restore-cloud.sh
4. Configure backup_restore.config
Open backup_restore.config and update the settings:

GH_REPO – your private repo name (e.g., "my-user/dotfiles-backup")

GPG_RECIPIENT_EMAIL – email of your public GPG key to enable encryption. Leave empty ("") to disable encryption.

BACKUP_PATHS – list of files/directories to include in backup. Use $HOME for universal paths.

⚡ Usage
💾 Backup
Run the backup script:

bash
Copy code
./backup-cloud.sh
Packs the defined files

Encrypts them (if configured)

Uploads to GitHub as a new Release

🔄 Restore
Run the restore script:

bash
Copy code
./restore-cloud.sh
Connects to GitHub

Lists the last 10 backups

Allows you to choose which backup to download and restore

🧪 Dry-Run Mode
Simulate the actions without making changes:

bash
Copy code
./backup-cloud.sh --dry-run
./restore-cloud.sh --dry-run
📄 License
This project is licensed under the MIT License.
