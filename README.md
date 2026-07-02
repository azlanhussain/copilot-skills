# Copilot Skills

A collection of GitHub Copilot CLI skills to simplify development workflows.

## Skills

| Skill | Description |
|-------|-------------|
| `openqc-prepare` | Prepare an automated QC test plan from git diff, PR description, and ticket requirements |
| `openqc-run` | Execute the QC test plan using Playwright (UI), MySQL (DB checks), and pdfplumber (PDF content) |
| `fix-review` | Attend to GitHub Copilot review comments — investigate, fix, commit individually, and reply in-thread |

## Installation

Run this one-liner in your terminal:

```bash
curl -s https://raw.githubusercontent.com/azlanhussain/copilot-skills/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/azlanhussain/copilot-skills.git ~/.copilot-skills-src
bash ~/.copilot-skills-src/install.sh
```

Re-run anytime to update to the latest version.

## Requirements

| Tool | Required by | Install |
|------|------------|---------|
| Node.js + npm | `openqc-run` | https://nodejs.org |
| Playwright + Chromium | `openqc-run` | Auto-installed on first run |
| Python 3 + pdfplumber | `openqc-run` | Auto-installed on first run (`pip3 install pdfplumber`) |
| GitHub CLI (`gh`) | `fix-review` | https://cli.github.com |
| Vagrant + Docker | `openqc-*` | Project-specific setup |

## Usage

In any GitHub Copilot CLI session, invoke by name:

```
openqc-prepare
openqc-prepare ~/Desktop/task-112662.txt
openqc-prepare read from branch changes and PR description
openqc-run
fix-review
```

Skills are available globally across all projects on your machine.
