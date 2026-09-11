# dotfiles-bootstrap

Öffentlicher Stage-0-Installer für das private Repository `pwnyprod/ultimate-dotfiles`.

```sh
curl -fsSL https://raw.githubusercontent.com/pwnyprod/dotfiles-bootstrap/main/install.sh | sh
```

Der Installer enthält keine privaten Daten und keine Tokens. Er prüft eine gepinnte GitHub-CLI per offiziellem SHA-256-Manifest, authentifiziert per GitHub-Web-Login und lädt danach das private, attestierte `dotctl`-Release.

Die kanonische Quelle liegt im privaten Repo unter `bootstrap/`; Änderungen werden erst dort getestet und anschließend in dieses kleine öffentliche Repo übertragen.
