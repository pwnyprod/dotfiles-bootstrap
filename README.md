# dotfiles-bootstrap

Öffentlicher Stage-0-Installer für das private Repository `pwnyprod/ultimate-dotfiles`.

```sh
curl -fsSL https://raw.githubusercontent.com/pwnyprod/dotfiles-bootstrap/main/install.sh | sh
```

Der Installer enthält keine privaten Daten und keine Tokens. Fehlt `gh`, lädt er eine gepinnte GitHub-CLI und prüft sie per offiziellem SHA-256-Manifest. Er authentifiziert per GitHub-Web-Login, lädt danach das private `dotctl`-Release und prüft es gegen `checksums.txt` sowie per gepinntem `cosign` gegen sein keyless Sigstore-Bundle.

## Windows

```powershell
irm https://raw.githubusercontent.com/pwnyprod/dotfiles-bootstrap/main/install.ps1 | iex
```

Mit Configure-Flags (werden unverändert an `dotctl configure` durchgereicht):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/pwnyprod/dotfiles-bootstrap/main/install.ps1))) --non-interactive --preset windows-workstation --email you@example.com
```

Voraussetzungen:

- Windows amd64 (ARM64 nutzt die amd64-Builds per x64-Emulation)
- Entwicklermodus an (Einstellungen → System → Für Entwickler), weil Repo und Agent-Pack echte Symlinks brauchen
- `winget` („App Installer“ aus dem Microsoft Store), falls Git noch fehlt
- Windows PowerShell 5.1 reicht; PowerShell 7 ist nicht nötig

`install.ps1` folgt derselben Prüfkette wie `install.sh` (gepinnte `gh`- und `cosign`-Binaries per SHA-256, `dotctl` per `checksums.txt` und Sigstore-Bundle) und legt `dotctl.exe` in `%USERPROFILE%\.local\bin` ab.

Dieses Repo ist die kanonische Quelle. Das private Repo bindet es als Git-Submodule unter `bootstrap/` ein und prüft `install.sh` dort in CI mit `bash -n` und ShellCheck. Hier prüft `.github/workflows/lint.yml` zusätzlich `install.ps1` per PowerShell-Parser (5.1 und 7) und PSScriptAnalyzer.
