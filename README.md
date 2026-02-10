# Mac Audit Script

This script performs a comprehensive audit of a macOS system, outputting the results in a markdown-formatted report.

## Usage

```bash
./mac-audit.sh [--md | --html | --both]
```

| Flag | Description |
|------|-------------|
| `--md` | Markdown output only (default) |
| `--html` | HTML output only |
| `--both` | Generate both markdown and HTML |

The HTML output is self-contained (no external dependencies) and includes dark mode support.

## Audited Sections:

*   System Information (macOS Version, Hardware)
*   Memory (RAM)
*   Storage (Disk Usage, SMART Status, Drive Type)
*   Time Machine Backup
*   Software Updates
*   Installed Applications (Key Applications, Homebrew Packages)
*   System Health (Uptime, Kernel Panics, Battery Health)
*   Network & Security (Network Interfaces, FileVault Status, Firewall Status)
*   User Accounts
*   Summary & Action Items

## Important Considerations for Unattended Execution

The primary concern for unattended execution on an unfamiliar machine is the rare but possible interactive prompt from `softwareupdate -l`.
