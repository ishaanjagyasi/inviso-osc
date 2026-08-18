#!/usr/bin/env bash
#
# One-step install for Inviso with OSC control, on macOS and Linux.
#
# Downloads the repo, sets everything up, and runs the site. Safe to re-run:
# an existing clone is updated rather than replaced.
#
#   ./bootstrap.sh [target-directory]
#
# The repo is private, so this needs either the GitHub CLI (gh auth login) or
# git credentials with access to it.

set -uo pipefail

REPO="ishaanjagyasi/inviso-osc"
TARGET="${1:-$PWD/inviso-osc}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m==>\033[0m %s\n' "$1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git is not installed."

if [ -d "$TARGET/.git" ]; then
  info "Found an existing clone at $TARGET, updating..."
  git -C "$TARGET" pull --ff-only || fail "Could not update $TARGET. Resolve local changes and re-run."
else
  [ -e "$TARGET" ] && fail "$TARGET already exists and is not a git clone."

  info "Cloning $REPO into $TARGET..."

  # gh handles auth for private repos without needing a stored git credential.
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh repo clone "$REPO" "$TARGET" || fail "Clone failed."
  else
    git clone "https://github.com/$REPO.git" "$TARGET" || fail \
      "Clone failed. The repo is private: run 'gh auth login', or set up a GitHub credential, then re-run."
  fi
fi

[ -f "$TARGET/setup.sh" ] || fail "setup.sh missing from $TARGET; the clone looks incomplete."

chmod +x "$TARGET/setup.sh" 2>/dev/null

info "Handing over to setup.sh..."
exec "$TARGET/setup.sh"
