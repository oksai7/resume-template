<#
Sets up LaTeX (MiKTeX) and everything resume.tex needs to compile and
preview as a PDF in VS Code, on Windows 11.

Safe to re-run any time -- every step checks whether it's already done
before doing it again.

What this does:
  1. Installs MiKTeX via winget (a LaTeX distribution for Windows)
  2. Enables MiKTeX's "install missing packages automatically" setting,
     and pre-installs the specific packages resume.tex needs: titlesec,
     marvosym, enumitem, preprint (provides fullpage.sty), and latexmk
  3. Points VS Code's LaTeX Workshop extension directly at those
     binaries (absolute paths + explicit PATH), so it works regardless
     of whether VS Code was launched before or after this install
  4. Compiles resume.tex once to confirm everything actually works

Run it by right-clicking this file -> "Run with PowerShell", or from a
PowerShell prompt:  .\setup-latex-windows.ps1
Neither step needs Administrator rights -- MiKTeX installs per-user.
#>

Write-Host "=== LaTeX setup for resume.tex (Windows) ===" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# --- 1. winget ---
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "winget isn't available. Install 'App Installer' from the Microsoft Store, then re-run this script." -ForegroundColor Red
    exit 1
}

# --- 2. MiKTeX: locate it, or install it ---
$candidates = @(
    "$env:LOCALAPPDATA\Programs\MiKTeX\miktex\bin\x64",
    "$env:PROGRAMFILES\MiKTeX\miktex\bin\x64"
)
$texbin = $candidates | Where-Object { Test-Path (Join-Path $_ "pdflatex.exe") } | Select-Object -First 1

if ($texbin) {
    Write-Host "MiKTeX already installed at $texbin, skipping install."
} else {
    Write-Host "Installing MiKTeX..."
    winget install --id MiKTeX.MiKTeX -e --silent --accept-package-agreements --accept-source-agreements
    $texbin = $candidates | Where-Object { Test-Path (Join-Path $_ "pdflatex.exe") } | Select-Object -First 1
}

if (-not $texbin) {
    Write-Host "Couldn't find MiKTeX's bin folder after install. Try reopening PowerShell and re-running this script." -ForegroundColor Red
    exit 1
}
Write-Host "Using MiKTeX binaries at $texbin"

# Add to this session's PATH, and persist for future terminal sessions
# (VS Code's own fix below doesn't depend on this, but a normal terminal
# needs it to just run `latexmk` by name).
$env:Path = "$texbin;$env:Path"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$texbin*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$texbin", "User")
}

# --- 3. Packages ---
Write-Host ""
Write-Host "Configuring MiKTeX to auto-install any other missing packages..."
try {
    & "$texbin\initexmf.exe" --set-config-value "[MPM]AutoInstall=1" 2>$null
} catch {
    Write-Host "  (Couldn't set that preference -- not critical, continuing.)" -ForegroundColor Yellow
}

Write-Host "Installing required LaTeX packages..."
& "$texbin\miktex.exe" packages update-package-database
foreach ($pkg in @("titlesec", "marvosym", "enumitem", "preprint", "latexmk")) {
    Write-Host "  - $pkg"
    & "$texbin\miktex.exe" packages install $pkg
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    Couldn't preinstall '$pkg' by name -- MiKTeX's auto-install will fetch it on first use instead." -ForegroundColor Yellow
    }
}

# --- 4. VS Code LaTeX Workshop config ---
$vscodeSettings = "$env:APPDATA\Code\User\settings.json"
$extDir = "$env:USERPROFILE\.vscode\extensions"

$hasLatexWorkshop = $false
if (Test-Path $extDir) {
    $hasLatexWorkshop = (Get-ChildItem $extDir -Directory -Filter "james-yu.latex-workshop*" -ErrorAction SilentlyContinue).Count -gt 0
}

if ($hasLatexWorkshop) {
    Write-Host ""
    Write-Host "Configuring VS Code's LaTeX Workshop extension..."

    $pathEnv = @{ Path = "$texbin;$env:SystemRoot\System32;$env:SystemRoot" }

    function New-LatexTool {
        param($Name, $Command, $ArgList)
        return [ordered]@{ name = $Name; command = $Command; args = $ArgList; env = $pathEnv }
    }

    $tools = @(
        (New-LatexTool "latexmk" "$texbin\latexmk.exe" @("-synctex=1","-interaction=nonstopmode","-file-line-error","-pdf","-outdir=%OUTDIR%","-auxdir=%AUXDIR%","%DOC%")),
        (New-LatexTool "lualatexmk" "$texbin\latexmk.exe" @("-synctex=1","-interaction=nonstopmode","-file-line-error","-lualatex","-outdir=%OUTDIR%","-auxdir=%AUXDIR%","%DOC%")),
        (New-LatexTool "xelatexmk" "$texbin\latexmk.exe" @("-synctex=1","-interaction=nonstopmode","-file-line-error","-xelatex","-outdir=%OUTDIR%","-auxdir=%AUXDIR%","%DOC%")),
        (New-LatexTool "latexmk_rconly" "$texbin\latexmk.exe" @("%DOC%")),
        (New-LatexTool "pdflatex" "$texbin\pdflatex.exe" @("-synctex=1","-interaction=nonstopmode","-file-line-error","%DOC%")),
        (New-LatexTool "bibtex" "$texbin\bibtex.exe" @("%DOCFILE%")),
        ([ordered]@{ name = "rnw2tex"; command = "Rscript"; args = @("-e","knitr::opts_knit`$set(concordance = TRUE); knitr::knit('%DOCFILE_EXT%')") }),
        ([ordered]@{ name = "jnw2tex"; command = "julia"; args = @("-e",'using Weave; weave("%DOC_EXT%", doctype="tex")') }),
        ([ordered]@{ name = "jnw2texminted"; command = "julia"; args = @("-e",'using Weave; weave("%DOC_EXT%", doctype="texminted")') }),
        ([ordered]@{ name = "pnw2tex"; command = "pweave"; args = @("-f","tex","%DOC_EXT%") }),
        ([ordered]@{ name = "pnw2texminted"; command = "pweave"; args = @("-f","texminted","%DOC_EXT%") }),
        ([ordered]@{ name = "tectonic"; command = "tectonic"; args = @("--synctex","--keep-logs","--print","%DOC%.tex") })
    )

    if (Test-Path $vscodeSettings) {
        Copy-Item $vscodeSettings "$vscodeSettings.bak" -Force -ErrorAction SilentlyContinue
        $raw = Get-Content $vscodeSettings -Raw
        $settings = if ([string]::IsNullOrWhiteSpace($raw)) { [PSCustomObject]@{} } else { $raw | ConvertFrom-Json }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $vscodeSettings) -Force | Out-Null
        $settings = [PSCustomObject]@{}
    }

    $settings | Add-Member -NotePropertyName "latex-workshop.kpsewhich.path" -NotePropertyValue "$texbin\kpsewhich.exe" -Force
    $settings | Add-Member -NotePropertyName "latex-workshop.latex.tools" -NotePropertyValue $tools -Force

    $json = $settings | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($vscodeSettings, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated $vscodeSettings"
} else {
    Write-Host ""
    Write-Host "VS Code LaTeX Workshop extension not found -- skipping editor config."
    Write-Host "(Install it from the Extensions panel: search 'LaTeX Workshop' by James Yu.)"
}

# --- 5. Verify by actually compiling resume.tex ---
$resumeTex = Join-Path $scriptDir "resume.tex"
if (Test-Path $resumeTex) {
    Write-Host ""
    Write-Host "Verifying by compiling resume.tex..."
    & "$texbin\latexmk.exe" -interaction=nonstopmode -pdf resume.tex *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Success -- resume.pdf compiled cleanly." -ForegroundColor Green
    } else {
        Write-Host "Something went wrong compiling resume.tex -- check resume.log for details." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "If VS Code is open, fully quit it and reopen it, then build resume.tex again."
