# ⚙️ github-release-dotfiles-backup
**Backup & restore your dotfiles, packages and tooling across multiple machines — using GitHub Releases.**  
A lightweight, practical tool to *replicate your working environment* on several computers quickly and safely.

---

## 🚀 Overview
This project creates an archive of your selected config files, package lists (APT / Flatpak / Snap / pip / npm / go) and system metadata, optionally encrypts it with GPG, and uploads it as a **GitHub Release**.  
Restore is interactive and safe — it takes a snapshot before changing files and offers rollback.

Perfect if you:
- maintain **multiple developer workstations** (your purpose: 3 machines),
- want a **one-command sync** of dotfiles + packages,
- need simple, auditable backups stored in your GitHub account.

---

# Features
- ✅ Create compressed backup archive (`backup_YYYY-MM-DD_HHMMSS.tar.gz`)  
- 🔒 Optional GPG encryption of archives  
- 🧾 Save package lists for apt, flatpak, snap, pip, npm, go  
- 🕒 Systemd timer-friendly (you already have it scheduled weekly)  
- ♻️ Cleanup old releases (keeps X latest)  
- 🧰 Restore that:  
  - makes a snapshot before modifying files  
  - validates backup contents  
  - offers rollback (`--rollback`)  
  - post-restore health checks for critical tools  
- 🧪 `--dry-run` support for safe testing  
- 📝 Colorful, readable logs for each step

---

# 📦 Quick Start

> **Prereqs (typical)**: `bash`, `gh` (GitHub CLI), `tar`, `gzip`, `gpg` (optional), `sudo` (for some restore steps), `pv` (optional progress).  
> Install any missing tool or accept warnings — script logs missing commands but continues where possible.

1. Clone repo:
```bash
git clone https://github.com/Xzar-x/github-release-dotfiles-backup.git
cd github-release-dotfiles-backup
```

2. Create and edit config:
```bash
cp backup_restore.config.example backup_restore.config
# edit backup_restore.config to point to your GH repo, backup paths and GPG recipient (optional)
```

3. Dry-run to verify what would happen:
```bash
./backup.sh --dry-run
```

4. Run real backup:
```bash
./backup.sh
```

5. Restore from an existing backup:
```bash
./restore-cloud.sh
# follow interactive menu to select release & sections to restore
```

6. Rollback last restore (if needed):
```bash
./restore-cloud.sh --rollback
```

---

# 🧩 Example `backup_restore.config` (template)
Place a real config at the script directory (`backup_restore.config`):

```ini
# backup_restore.config (example)
GH_REPO="youruser/your-private-backup-repo"
GPG_RECIPIENT_EMAIL="you@example.com"        # optional: leave empty to disable encryption
LOG_FILE="$HOME/.backup_logs/backup.log"
# paths to back up (absolute or relative)
BACKUP_PATHS=( "$HOME/.zshrc" "$HOME/.config" "$HOME/.ssh" )
KEEP_LATEST_RELEASES=5
# optional: array of go tools for restore if .log_go_packages.txt missing
GO_TOOLS_TO_BACKUP=( "github.com/golangci/golangci-lint/cmd/golangci-lint@latest" )
```

> **Important:** Do **not** commit your real `backup_restore.config` with secrets or tokens. Add it to `.gitignore` if needed.

---

# ⏰ Systemd examples

## 1) Backup timer — *every 2 days (two common approaches)*

**a) Repeat every 48 hours (independent of calendar dates)**  
`/etc/systemd/system/backup.service`
```ini
[Unit]
Description=Run dotfiles backup (oneshot)

[Service]
Type=oneshot
WorkingDirectory=/path/to/github-release-dotfiles-backup
ExecStart=/path/to/github-release-dotfiles-backup/backup.sh
```

`/etc/systemd/system/backup.timer`
```ini
[Unit]
Description=Run dotfiles backup every 48 hours

[Timer]
OnBootSec=10min
OnUnitActiveSec=2d
Persistent=true

[Install]
WantedBy=timers.target
```

**b) Calendar-based: every other day (even days)**  
If you prefer calendar parity:
```ini
[Timer]
OnCalendar=*-*-*~2
Persistent=true
```
> Note: `*-*-*~2` triggers on even calendar days (2,4,6,...). Use `OnUnitActiveSec=2d` for exact 48h gaps.

**Enable:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer
systemctl list-timers | grep backup
```

---

## 2) Daily cleanup timer (remove `.pre_restored*` older than 14 days)
`/etc/systemd/system/backup-clean.service`
```ini
[Unit]
Description=Cleanup old pre_restored files

[Service]
Type=oneshot
ExecStart=/usr/bin/find /home/youruser -name "*.pre_restored*" -type f -mtime +14 -delete
```

`/etc/systemd/system/backup-clean.timer`
```ini
[Unit]
Description=Run backup-clean once a day

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

Enable it:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now backup-clean.timer
```

---

# 🔍 How it works (simple flow)
```
backup.sh
  ├─ prepare BACKUP_DIR
  ├─ copy selected files → BACKUP_DIR
  ├─ save system metadata & package lists
  ├─ tar + gzip (pipe via pv if available)
  ├─ optional: encrypt with gpg -> .gpg file
  └─ upload to GitHub Releases using `gh`
        └─ cleanup_old_releases() keeps latest N releases
```

Restore (`restore-cloud.sh`) does:
- list releases (gh)
- download selected archive
- decrypt (if needed)
- unpack to temp folder
- validate content
- create a snapshot of existing configs
- interactively restore sections (config files, apt, debs, flatpak, snap, pip, npm, go, git repos)
- post-restore health check
- show restore summary
- offer rollback via stored snapshot

---

# 🔐 Security & best practices
- **Make the GitHub repo private.** The script checks that the repo is private before uploading.  
- Use a **minimal-purpose GitHub token** for `gh` CLI (scopes needed: `repo` for releases; choose least privilege necessary).  
- Keep `backup_restore.config` private — do not push it to a public repo.  
- If using GPG encryption, ensure recipient public key is present on the machine that *creates* backups; private key is needed only for *decrypting* restores on machines you trust.  
- Validate `gh` authentication (`gh auth status`) before running the real backup.

---

# 🧪 Testing & troubleshooting
- Always run `./backup.sh --dry-run` to check operations without making changes.  
- Check logs (if `LOG_FILE` set in config) or run the script interactively to see colored output.  
- If upload fails: check `gh` auth and repo visibility.  
- If restore fails: use `./restore-cloud.sh --rollback` to revert to last snapshot.

---

# ♻️ Maintenance notes
- `KEEP_LATEST_RELEASES` controls how many releases you keep; older ones are deleted automatically by `cleanup_old_releases()`.  
- Add a `backup-clean` timer (example above) to automatically remove `.pre_restored*` files older than N days to avoid clutter.  
- If you want backup frequency different than weekly, change the systemd timer as described earlier.

---

# 📜 License
This project is **MIT-licensed** — feel free to adapt for personal or internal use. (Add `LICENSE` file if you want explicit text.)

---

# 🤝 Contributing / Support
This repo is designed as a personal tool — but if you want it to be more widely reusable, I can help:
- turn config into a clearer templated `config.example`,
- add CI checks (shellcheck),
- add unit/integration tests (mock releases),
- make an installer to register systemd units automatically.

---

# 🙋‍♂️ Final words
You built a practical, high-value tool — your three machines now sync reliably and you’ve automated a pain point many devs live with. Nicely done. 👏  
If you want, I can now:
- produce `README.md` as a file you can paste into GitHub (done above), or
- create the systemd `.service/.timer` files (with correct absolute paths) ready to `sudo cp` into `/etc/systemd/system/`.
