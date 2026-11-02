#!/bin/bash
# Sets up LaTeX (BasicTeX) and everything resume.tex needs to compile and
# preview as a PDF in VS Code, on macOS.
#
# Safe to double-click and re-run any time — every step checks whether it's
# already done before doing it again.
#
# What this does:
#   1. Installs BasicTeX via Homebrew (a minimal TeX Live distribution)
#   2. Installs the specific LaTeX packages resume.tex needs: titlesec,
#      marvosym, enumitem, preprint (provides fullpage.sty), and latexmk
#   3. Points VS Code's LaTeX Workshop extension directly at those
#      binaries (absolute paths + explicit PATH), so it works regardless
#      of whether VS Code was launched before or after this install
#   4. Compiles resume.tex once to confirm everything actually works

set -e

cd "$(dirname "$0")"

echo "=== LaTeX setup for resume.tex (macOS) ==="
echo

# --- 1. Homebrew ---
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew isn't installed. Install it from https://brew.sh, then re-run this script."
  exit 1
fi

# --- 2. BasicTeX ---
TEXBIN="/Library/TeX/texbin"

if brew list --cask basictex >/dev/null 2>&1; then
  echo "BasicTeX already installed, skipping."
else
  echo "Installing BasicTeX — this will ask for your Mac password."
  brew install --cask basictex
fi

export PATH="$TEXBIN:$PATH"

if ! [ -x "$TEXBIN/tlmgr" ]; then
  echo "tlmgr not found at $TEXBIN — the BasicTeX install may not have finished correctly."
  exit 1
fi

# --- 3. Required packages ---
echo
echo "Installing required LaTeX packages — this will ask for your password again."
sudo "$TEXBIN/tlmgr" update --self
sudo "$TEXBIN/tlmgr" install titlesec marvosym enumitem preprint latexmk

# --- 4. VS Code LaTeX Workshop config ---
VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
EXT_DIR="$HOME/.vscode/extensions"

HAS_LATEX_WORKSHOP=0
if [ -d "$EXT_DIR" ] && ls "$EXT_DIR" 2>/dev/null | grep -qi "james-yu.latex-workshop"; then
  HAS_LATEX_WORKSHOP=1
fi

if [ "$HAS_LATEX_WORKSHOP" = "1" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo
    echo "python3 not found — can't auto-configure VS Code. See the chat for the settings.json to add manually."
  else
    echo
    echo "Configuring VS Code's LaTeX Workshop extension..."
    python3 - "$VSCODE_SETTINGS" "$TEXBIN" <<'PYEOF'
import json, os, sys

settings_path, texbin = sys.argv[1], sys.argv[2]
os.makedirs(os.path.dirname(settings_path), exist_ok=True)

if os.path.exists(settings_path):
    with open(settings_path) as f:
        raw = f.read().strip()
    settings = json.loads(raw) if raw else {}
    backup_path = settings_path + ".bak"
    if not os.path.exists(backup_path):
        with open(backup_path, "w") as f:
            f.write(raw)
        print(f"Backed up existing settings to {backup_path}")
else:
    settings = {}

path_env = {"PATH": f"{texbin}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}

def tool(name, command, args):
    return {"name": name, "command": command, "args": args, "env": path_env}

settings["latex-workshop.kpsewhich.path"] = f"{texbin}/kpsewhich"
settings["latex-workshop.latex.tools"] = [
    tool("latexmk", f"{texbin}/latexmk", [
        "-synctex=1", "-interaction=nonstopmode", "-file-line-error", "-pdf",
        "-outdir=%OUTDIR%", "-auxdir=%AUXDIR%", "%DOC%",
    ]),
    tool("lualatexmk", f"{texbin}/latexmk", [
        "-synctex=1", "-interaction=nonstopmode", "-file-line-error", "-lualatex",
        "-outdir=%OUTDIR%", "-auxdir=%AUXDIR%", "%DOC%",
    ]),
    tool("xelatexmk", f"{texbin}/latexmk", [
        "-synctex=1", "-interaction=nonstopmode", "-file-line-error", "-xelatex",
        "-outdir=%OUTDIR%", "-auxdir=%AUXDIR%", "%DOC%",
    ]),
    tool("latexmk_rconly", f"{texbin}/latexmk", ["%DOC%"]),
    tool("pdflatex", f"{texbin}/pdflatex", [
        "-synctex=1", "-interaction=nonstopmode", "-file-line-error", "%DOC%",
    ]),
    tool("bibtex", f"{texbin}/bibtex", ["%DOCFILE%"]),
    {"name": "rnw2tex", "command": "Rscript", "args": [
        "-e", "knitr::opts_knit$set(concordance = TRUE); knitr::knit('%DOCFILE_EXT%')",
    ]},
    {"name": "jnw2tex", "command": "julia", "args": [
        "-e", 'using Weave; weave("%DOC_EXT%", doctype="tex")',
    ]},
    {"name": "jnw2texminted", "command": "julia", "args": [
        "-e", 'using Weave; weave("%DOC_EXT%", doctype="texminted")',
    ]},
    {"name": "pnw2tex", "command": "pweave", "args": ["-f", "tex", "%DOC_EXT%"]},
    {"name": "pnw2texminted", "command": "pweave", "args": ["-f", "texminted", "%DOC_EXT%"]},
    {"name": "tectonic", "command": "tectonic", "args": [
        "--synctex", "--keep-logs", "--print", "%DOC%.tex",
    ]},
]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=4)
    f.write("\n")

print(f"Updated {settings_path}")
PYEOF
  fi
else
  echo
  echo "VS Code LaTeX Workshop extension not found — skipping editor config."
  echo "(Install it from the Extensions panel: search 'LaTeX Workshop' by James Yu.)"
fi

# --- 5. Verify by actually compiling resume.tex ---
if [ -f "resume.tex" ]; then
  echo
  echo "Verifying by compiling resume.tex..."
  if "$TEXBIN/latexmk" -interaction=nonstopmode -pdf resume.tex >/dev/null 2>&1; then
    echo "Success — resume.pdf compiled cleanly."
  else
    echo "Something went wrong compiling resume.tex — check resume.log for details."
  fi
fi

echo
echo "=== Done ==="
echo "If VS Code is open, fully quit it (Cmd+Q) and reopen it, then build resume.tex again."
