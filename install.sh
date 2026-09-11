#!/bin/sh
set -eu

private_repo=${DOTFILES_GITHUB_REPO:-pwnyprod/ultimate-dotfiles}
repo_dir=${DOTFILES_DIR:-"$HOME/.dotfiles"}
bin_dir=${DOTFILES_BIN_DIR:-"$HOME/.local/bin"}
gh_version=${GH_VERSION:-2.100.0}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

checksum() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$@"
	else
		shasum -a 256 "$@"
	fi
}

install_gh() {
	os=$(uname -s)
	arch=$(uname -m)
	case "$os/$arch" in
		Darwin/arm64) platform=macOS_arm64; archive="gh_${gh_version}_${platform}.zip" ;;
		Linux/x86_64) platform=linux_amd64; archive="gh_${gh_version}_${platform}.tar.gz" ;;
		Linux/aarch64|Linux/arm64) platform=linux_arm64; archive="gh_${gh_version}_${platform}.tar.gz" ;;
		*) printf 'Nicht unterstützte Bootstrap-Plattform: %s/%s\n' "$os" "$arch" >&2; exit 1 ;;
	esac
	base="https://github.com/cli/cli/releases/download/v${gh_version}"
	curl -fsSL "$base/gh_${gh_version}_checksums.txt" -o "$scratch/gh-checksums.txt"
	curl -fsSL "$base/$archive" -o "$scratch/$archive"
	expected=$(awk -v file="$archive" '$2 == file { print $1 }' "$scratch/gh-checksums.txt")
	actual=$(checksum "$scratch/$archive" | awk '{print $1}')
	[ -n "$expected" ] && [ "$expected" = "$actual" ] || { printf 'Checksum-Prüfung für gh fehlgeschlagen.\n' >&2; exit 1; }
	case "$archive" in
		*.zip) ditto -x -k "$scratch/$archive" "$scratch/gh" ;;
		*) mkdir -p "$scratch/gh"; tar -xzf "$scratch/$archive" -C "$scratch/gh" ;;
	esac
	GH_BIN=$(find "$scratch/gh" -type f -path '*/bin/gh' -print -quit)
	[ -n "$GH_BIN" ] || { printf 'gh-Binary nicht im Archiv gefunden.\n' >&2; exit 1; }
}

if command -v gh >/dev/null 2>&1; then
	GH_BIN=$(command -v gh)
else
	install_gh
fi

if ! "$GH_BIN" auth status --hostname github.com >/dev/null 2>&1; then
	[ -r /dev/tty ] || { printf 'GitHub-Login benötigt ein interaktives Terminal.\n' >&2; exit 1; }
	"$GH_BIN" auth login --hostname github.com --web --git-protocol https --scopes repo </dev/tty
fi

if [ -d "$repo_dir/.git" ]; then
	git -C "$repo_dir" pull --ff-only
elif [ -e "$repo_dir" ]; then
	printf '%s existiert, ist aber kein Git-Repository.\n' "$repo_dir" >&2
	exit 1
else
	"$GH_BIN" repo clone "$private_repo" "$repo_dir"
fi

dotctl_version=$(tr -d '[:space:]' < "$repo_dir/dotctl.version")
case "$(uname -s)/$(uname -m)" in
	Darwin/arm64) asset=dotctl-darwin-arm64 ;;
	Linux/x86_64) asset=dotctl-linux-amd64 ;;
	Linux/aarch64|Linux/arm64) asset=dotctl-linux-arm64 ;;
	*) printf 'Keine dotctl-Release für diese Plattform.\n' >&2; exit 1 ;;
esac

"$GH_BIN" release download "dotctl-v${dotctl_version}" --repo "$private_repo" --dir "$scratch" --pattern "$asset" --pattern checksums.txt
expected=$(awk -v file="$asset" '$2 == file { print $1 }' "$scratch/checksums.txt")
actual=$(checksum "$scratch/$asset" | awk '{print $1}')
[ -n "$expected" ] && [ "$expected" = "$actual" ] || { printf 'Checksum-Prüfung für dotctl fehlgeschlagen.\n' >&2; exit 1; }
"$GH_BIN" attestation verify "$scratch/$asset" --repo "$private_repo" >/dev/null
mkdir -p "$bin_dir"
install -m 0755 "$scratch/$asset" "$bin_dir/dotctl"

if [ -r /dev/tty ]; then
	"$bin_dir/dotctl" --repo "$repo_dir" configure "$@" </dev/tty
else
	"$bin_dir/dotctl" --repo "$repo_dir" configure "$@"
fi
"$bin_dir/dotctl" --repo "$repo_dir" plan
if [ -r /dev/tty ]; then
	"$bin_dir/dotctl" --repo "$repo_dir" apply </dev/tty
else
	"$bin_dir/dotctl" --repo "$repo_dir" apply
fi
