#!/bin/sh
#
# Install git hooks from .githooks/ directory
#

HOOKS_DIR=".githooks"
GIT_HOOKS_DIR=".git/hooks"

if [ ! -d "$GIT_HOOKS_DIR" ]; then
  echo "Error: .git/hooks directory not found. Are you in the repository root?"
  exit 1
fi

echo "Installing git hooks..."

for hook in "$HOOKS_DIR"/*; do
  if [ -f "$hook" ]; then
    hook_name=$(basename "$hook")
    
    # Skip non-hook files
    if [ "$hook_name" = "install.sh" ] || [ "$hook_name" = "README.md" ]; then
      continue
    fi
    
    cp "$hook" "$GIT_HOOKS_DIR/$hook_name"
    chmod +x "$GIT_HOOKS_DIR/$hook_name"
    echo "✓ Installed $hook_name"
  fi
done

echo ""
echo "Git hooks installed successfully!"
echo "The pre-commit hook will run 'mix format' on staged Elixir and Phoenix files (.ex, .exs, .heex)."
