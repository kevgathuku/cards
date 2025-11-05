# Git Hooks

This directory contains git hooks that can be installed to enhance the development workflow.

## Available Hooks

### pre-commit

Automatically runs `mix format` on staged Elixir and Phoenix files before each commit.

**Behavior**:
- Runs only when `.ex`, `.exs`, or `.heex` files are staged
- Formats the staged files
- If formatting makes changes, the commit is aborted and you need to re-stage the files
- If no formatting changes are needed, the commit proceeds

**Why this helps**:
- Ensures consistent code style across the project
- Prevents formatting-only commits
- Catches formatting issues before code review

## Installation

From the project root directory, run:

```bash
.githooks/install.sh
```

This will copy all hooks from `.githooks/` to `.git/hooks/` and make them executable.

## Skipping Hooks

If you need to skip the pre-commit hook for a specific commit (not recommended):

```bash
git commit --no-verify
```

## Manual Installation

If the install script doesn't work, you can manually install hooks:

```bash
cp .githooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```
