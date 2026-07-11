#!/usr/bin/env bash
# Start argo-shim in a persistent tmux session on a Bebop login node.
#
# Automates the Section 3 steps from claude-on-lcrc.md:
#   tmux new -s argo-shim
#   source argovenv/bin/activate
#   eval "$(ssh-agent -s)"; ssh-add ~/.ssh/id_ed25519   # prompts for passphrase
#   argo-shim
#
# It re-launches itself *inside* the tmux session and attaches, so the ssh-add
# passphrase prompt and the argo-shim Duo prompt appear where you can respond.
# After you see "✅ All health checks passed", detach with:  Ctrl-b d
#
# Usage:
#   ./start-argo-shim.sh                      # regular login-node argo-shim
#   ./start-argo-shim.sh --tunnel --tunnel-port <BASE_PORT+2>   # §7 tunnel variant
#                                             # (use SESSION=argo-shim-tunnel for this)
#
# Overridable via environment:
#   SESSION   tmux session name        (default: argo-shim)
#   ARGOVENV  path to the venv          (default: $HOME/argovenv)
#   SSH_KEY   private key to ssh-add    (default: $HOME/.ssh/id_ed25519)

set -euo pipefail

SESSION="${SESSION:-argo-shim}"
ARGOVENV="${ARGOVENV:-$HOME/argovenv}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

# Absolute path to this script, so tmux can re-exec it regardless of cwd.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---------- worker: runs inside the tmux session ----------
if [[ "${1:-}" == "__inner__" ]]; then
  shift  # drop the sentinel; remaining args ("$@") pass through to argo-shim

  # shellcheck disable=SC1091
  source "$ARGOVENV/bin/activate"

  # Reuse an existing ssh-agent if one is reachable; otherwise start a fresh one.
  # ssh-add -l exit codes: 0 = agent has identities, 1 = agent up but empty,
  #                        2 = no agent reachable.
  ssh-add -l >/dev/null 2>&1 && rc=0 || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    eval "$(ssh-agent -s)"
    rc=1
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo ">>> Adding SSH key ($SSH_KEY) — enter its passphrase when prompted:"
    ssh-add "$SSH_KEY"
  else
    echo ">>> SSH key already loaded in the agent — no passphrase needed."
  fi

  echo ">>> Starting argo-shim. Approve the Duo push, then wait for '✅ All health checks passed'."
  echo ">>> When healthy, detach with:  Ctrl-b d   (argo-shim keeps running)"
  argo-shim "$@" || true

  # Keep the pane alive so any exit/error output stays visible.
  echo
  echo ">>> argo-shim exited. Dropping to a shell (venv still active). Ctrl-d to close."
  exec "${SHELL:-bash}"
fi

# ---------- launcher: runs in your normal shell ----------
command -v tmux >/dev/null 2>&1 || { echo "error: tmux not found on PATH" >&2; exit 1; }
[[ -f "$ARGOVENV/bin/activate" ]] || {
  echo "error: venv not found at $ARGOVENV (see claude-on-lcrc.md §2 to create it)" >&2; exit 1; }
[[ -f "$SSH_KEY" ]] || { echo "error: SSH key not found at $SSH_KEY" >&2; exit 1; }

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already exists — attaching (Ctrl-b d to detach)."
  exec tmux attach -t "$SESSION"
fi

echo "Creating tmux session '$SESSION' and attaching..."
exec tmux new-session -s "$SESSION" "$SELF" __inner__ "$@"
