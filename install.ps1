# Stage-0-Installer fuer natives Windows; Pendant zu install.sh.
# Laeuft unter Windows PowerShell 5.1 und pwsh 7. Wird per `irm | iex` ausgefuehrt:
# daher kein `exit`, Fehler werden per `throw` gemeldet.
# Bewusst nur ASCII: Windows PowerShell 5.1 liest BOM-lose Dateien als ANSI.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $configureArgs = @($args)

    function Write-Step {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interaktiver Installer: Statusmeldungen gehoeren auf die Konsole, nicht in die Pipeline.')]
        param([string]$Message)
        Write-Host "==> $Message" -ForegroundColor Cyan
    }

    function Invoke-Native {
        param([string]$FilePath, [string[]]$ArgumentList)
        # Stderr nativer Tools (z. B. git-Fortschritt) darf in Nicht-Konsolen-Hosts nicht abbrechen.
        $ErrorActionPreference = 'Continue'
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "Befehl fehlgeschlagen (Exit-Code $LASTEXITCODE): $FilePath $($ArgumentList -join ' ')"
        }
    }

    function Get-ExpectedHash {
        param([string]$ChecksumFile, [string]$FileName)
        foreach ($line in Get-Content -LiteralPath $ChecksumFile) {
            $parts = $line.Trim() -split '\s+', 2
            if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $FileName) {
                return $parts[0]
            }
        }
        return ''
    }

    function Assert-Sha256 {
        param([string]$Path, [string]$Expected, [string]$Name)
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
        # -ne vergleicht case-insensitiv; Get-FileHash liefert Grossbuchstaben.
        if (-not $Expected -or $actual -ne $Expected) {
            throw "Checksum-Pruefung fuer $Name fehlgeschlagen."
        }
    }

    function Get-File {
        param([string]$Uri, [string]$OutFile)
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
    }

    $privateRepo = $env:DOTFILES_GITHUB_REPO
    if (-not $privateRepo) { $privateRepo = 'pwnyprod/ultimate-dotfiles' }
    $repoDir = $env:DOTFILES_DIR
    if (-not $repoDir) { $repoDir = Join-Path $HOME '.dotfiles' }
    $binDir = $env:DOTFILES_BIN_DIR
    if (-not $binDir) { $binDir = Join-Path (Join-Path $HOME '.local') 'bin' }
    $ghVersion = $env:GH_VERSION
    if (-not $ghVersion) { $ghVersion = '2.100.0' }
    $cosignVersion = $env:COSIGN_VERSION
    if (-not $cosignVersion) { $cosignVersion = '3.1.3' }
    # SHA-256 von cosign-windows-amd64.exe aus cosign_checksums.txt des Releases v3.1.3.
    $cosignSha256 = '9fe59be0eca1271873ce019061335eb1ac419b7059202e797828467ddabe33be'

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'install.ps1 ist nur fuer Windows. Auf macOS/Linux install.sh verwenden.'
    }
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    # shortcut: ARM64-Windows nutzt die amd64-Assets per x64-Emulation; native arm64-Builds erst, wenn dotctl sie released.
    if ($arch -ne 'AMD64' -and $arch -ne 'ARM64') {
        throw "Nicht unterstuetzte Bootstrap-Plattform: Windows/$arch (benoetigt AMD64 oder ARM64)."
    }

    $devMode = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
    if (-not $devMode -or $devMode.AllowDevelopmentWithoutDevLicense -ne 1) {
        throw 'Der Windows-Entwicklermodus ist aus. Das Agent-Pack braucht echte Symlinks: Einstellungen -> System -> Fuer Entwickler -> Entwicklermodus einschalten und install.ps1 erneut starten.'
    }

    $scratch = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-bootstrap-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch | Out-Null
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                throw 'git fehlt und winget ist nicht verfuegbar. "App Installer" aus dem Microsoft Store installieren bzw. aktualisieren und install.ps1 erneut starten.'
            }
            Write-Step 'Installiere Git per winget'
            Invoke-Native winget @('install', '--exact', '--id', 'Git.Git', '--silent', '--accept-package-agreements', '--accept-source-agreements')
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                throw 'git wurde installiert, ist aber nicht im PATH. Neues Terminal oeffnen und install.ps1 erneut starten.'
            }
        }

        $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
        if ($ghCommand) {
            $gh = $ghCommand.Source
        } else {
            Write-Step "Lade GitHub CLI $ghVersion"
            $archive = "gh_${ghVersion}_windows_amd64.zip"
            $base = "https://github.com/cli/cli/releases/download/v$ghVersion"
            $ghChecksums = Join-Path $scratch 'gh-checksums.txt'
            Get-File "$base/gh_${ghVersion}_checksums.txt" $ghChecksums
            Get-File "$base/$archive" (Join-Path $scratch $archive)
            Assert-Sha256 (Join-Path $scratch $archive) (Get-ExpectedHash $ghChecksums $archive) 'gh'
            Expand-Archive -LiteralPath (Join-Path $scratch $archive) -DestinationPath (Join-Path $scratch 'gh')
            $gh = Join-Path $scratch 'gh\bin\gh.exe'
            if (-not (Test-Path -LiteralPath $gh)) { throw 'gh.exe nicht im Archiv gefunden.' }
        }

        $loggedIn = & {
            $ErrorActionPreference = 'Continue'
            & $gh auth status --hostname github.com *> $null
            $LASTEXITCODE -eq 0
        }
        if (-not $loggedIn) {
            Write-Step 'GitHub-Login (Browser)'
            Invoke-Native $gh @('auth', 'login', '--hostname', 'github.com', '--web', '--git-protocol', 'https', '--scopes', 'repo')
        }

        Invoke-Native git @('config', '--global', 'core.symlinks', 'true')
        if (Test-Path -LiteralPath (Join-Path $repoDir '.git')) {
            Write-Step "Aktualisiere $repoDir"
            Invoke-Native git @('-C', $repoDir, 'pull', '--ff-only')
        } elseif (Test-Path -LiteralPath $repoDir) {
            throw "$repoDir existiert, ist aber kein Git-Repository."
        } else {
            Write-Step "Klone $privateRepo nach $repoDir"
            Invoke-Native $gh @('repo', 'clone', $privateRepo, $repoDir, '--', '-c', 'core.symlinks=true')
        }
        $claudeMd = Get-Item -LiteralPath (Join-Path $repoDir 'CLAUDE.md') -Force -ErrorAction SilentlyContinue
        if (-not $claudeMd -or $claudeMd.LinkType -ne 'SymbolicLink') {
            throw "$repoDir\CLAUDE.md ist kein Symlink. Entwicklermodus und 'git config --global core.symlinks true' pruefen, $repoDir loeschen und install.ps1 erneut starten."
        }

        $dotctlVersion = (Get-Content -Raw -LiteralPath (Join-Path $repoDir 'dotctl.version')).Trim()
        $asset = 'dotctl-windows-amd64.exe'
        $assetPath = Join-Path $scratch $asset
        Write-Step "Lade dotctl $dotctlVersion"
        Invoke-Native $gh @('release', 'download', "dotctl-v$dotctlVersion", '--repo', $privateRepo, '--dir', $scratch, '--pattern', $asset, '--pattern', "$asset.sigstore.json", '--pattern', 'checksums.txt')
        Assert-Sha256 $assetPath (Get-ExpectedHash (Join-Path $scratch 'checksums.txt') $asset) 'dotctl'

        $cosign = Join-Path $scratch 'cosign.exe'
        Get-File "https://github.com/sigstore/cosign/releases/download/v$cosignVersion/cosign-windows-amd64.exe" $cosign
        Assert-Sha256 $cosign $cosignSha256 'cosign'
        Write-Step 'Pruefe dotctl-Signatur (Sigstore)'
        Invoke-Native $cosign @('verify-blob', $assetPath,
            '--bundle', "$assetPath.sigstore.json",
            '--certificate-identity', "https://github.com/$privateRepo/.github/workflows/dotctl-release.yml@refs/tags/dotctl-v$dotctlVersion",
            '--certificate-oidc-issuer', 'https://token.actions.githubusercontent.com')

        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        $dotctl = Join-Path $binDir 'dotctl.exe'
        Copy-Item -LiteralPath $assetPath -Destination $dotctl -Force

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not $userPath) { $userPath = '' }
        if (($userPath -split ';') -notcontains $binDir) {
            [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $binDir).TrimStart(';'), 'User')
        }
        if (($env:Path -split ';') -notcontains $binDir) {
            $env:Path = "$binDir;$env:Path"
        }

        Invoke-Native $dotctl (@('--repo', $repoDir, 'configure') + $configureArgs)
        Invoke-Native $dotctl @('--repo', $repoDir, 'plan')
        Invoke-Native $dotctl @('--repo', $repoDir, 'apply')

        Write-Step 'Fertig. Neues Terminal oeffnen (PATH aktualisiert) und "dotctl doctor" ausfuehren.'
    } finally {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
} @args
