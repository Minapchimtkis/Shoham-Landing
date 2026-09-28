#!/bin/bash
# Claude Code on the web starts each session in a fresh container, so anything
# installed by hand is gone by the next one. This puts the frontend-design
# plugin back before the session begins.
#
# There is nothing else to install: the site is static, with no build step and
# no dependency manifest, which is why this hook does only this one thing.
set -euo pipefail

# Only on the web. A local checkout keeps whatever the person installed there.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

MARKET="claude-plugins-official"
PLUGIN="frontend-design"

# The marketplace is not registered in a fresh container, and installing from
# one that is not registered fails.
if ! claude plugin marketplace list 2>/dev/null | grep -q "$MARKET"; then
  claude plugin marketplace add "anthropics/$MARKET" || {
    echo "could not add the $MARKET marketplace; carrying on without the plugin" >&2
    exit 0
  }
fi

# Safe to run again: an already-installed plugin is left alone.
if claude plugin list 2>/dev/null | grep -q "$PLUGIN@$MARKET"; then
  echo "$PLUGIN is already installed"
  exit 0
fi

claude plugin install "$PLUGIN@$MARKET" || {
  echo "could not install $PLUGIN; carrying on without it" >&2
  exit 0
}
