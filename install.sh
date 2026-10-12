#!/bin/sh
# Install madal from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/pa/madal-releases/main/install.sh | sh
#
# It downloads the archive for this OS and CPU, checks its SHA-256 against the
# release's checksums.txt, and installs the binary into $MADAL_INSTALL_DIR
# (default ~/.local/bin). Set MADAL_VERSION=v0.1.1 to pin a version.
set -eu

repo="pa/madal-releases"
dir="${MADAL_INSTALL_DIR:-$HOME/.local/bin}"

fail() { echo "madal install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "needs $1"; }
need curl
need tar
need uname

# One of GitHub's download addresses doesn't answer from some networks, and
# curl waits over a minute on it before trying the next. A short connect
# timeout makes it move on in a second or two.
dl() { curl -fL --connect-timeout 4 --retry 2 "$@"; }

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail "unsupported OS $(uname -s); on Windows, download the zip from https://github.com/$repo/releases" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) fail "unsupported CPU $(uname -m)" ;;
esac

version="${MADAL_VERSION:-}"
if [ -z "$version" ]; then
  version=$(dl -sS "https://api.github.com/repos/$repo/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
  [ -n "$version" ] || fail "couldn't find the latest release"
fi

name="madal_${version#v}_${os}_${arch}"
base="https://github.com/$repo/releases/download/$version"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading madal $version for $os/$arch"
dl --progress-bar -o "$tmp/$name.tar.gz" "$base/$name.tar.gz"
echo "Downloading checksums"
dl -sS -o "$tmp/checksums.txt" "$base/checksums.txt"

want=$(grep " $name.tar.gz\$" "$tmp/checksums.txt" | cut -d' ' -f1)
[ -n "$want" ] || fail "no checksum listed for $name.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$tmp/$name.tar.gz" | cut -d' ' -f1)
else
  got=$(shasum -a 256 "$tmp/$name.tar.gz" | cut -d' ' -f1)
fi
[ "$got" = "$want" ] || fail "checksum mismatch for $name.tar.gz; not installing"
echo "Checksum verified"

tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
mkdir -p "$dir"
install -m 0755 "$tmp/$name/madal" "$dir/madal"
echo "Installed $dir/madal"

case ":$PATH:" in
  *":$dir:"*) ;;
  *) echo "Add $dir to your PATH, for example: export PATH=\"$dir:\$PATH\"" ;;
esac
echo "Next: madal login"
