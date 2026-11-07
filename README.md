# dotfiles-bootstrap

Öffentlicher Stage-0-Installer für das private Repository `pwnyprod/ultimate-dotfiles`.

```sh
curl -fsSL https://raw.githubusercontent.com/pwnyprod/dotfiles-bootstrap/main/install.sh | sh
```

Der Installer enthält keine privaten Daten und keine Tokens. Fehlt `gh`, lädt er eine gepinnte GitHub-CLI und prüft sie per offiziellem SHA-256-Manifest. Er authentifiziert per GitHub-Web-Login, lädt danach das private `dotctl`-Release und prüft es gegen `checksums.txt` sowie per gepinntem `cosign` gegen sein keyless Sigstore-Bundle.

Dieses Repo ist die kanonische Quelle. Das private Repo bindet es als Git-Submodule unter `bootstrap/` ein und prüft `install.sh` dort in CI mit `bash -n` und ShellCheck.
