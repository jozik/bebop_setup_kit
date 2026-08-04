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
#   ./start-argo-shim.sh            # regular login-node shim   (session: argo-shim)
#   ./start-argo-shim.sh --tunnel   # §7 tunnel for compute use (session: argo-shim-tunnel)
#   ./start-argo-shim.sh --all      # both sessions, one passphrase and one Duo
#
# --all starts the two sessions *sequentially*: the regular shim first (you
# approve Duo there), then the tunnel, which reuses what the first established
# and needs no input. Starting them in parallel would race and can produce two
# Duo prompts, so don't. The SSH key is loaded once in your own shell and the
# agent is handed to both sessions, so you type the passphrase a single time.
#
# In --tunnel mode this script computes --tunnel-port for you as shim_port + 1,
# where shim_port is derived from your username exactly as argo-shim does
# (matching agent-bits/argo-shim.qsub). Pass --tunnel-port yourself to override.
# Any extra args are forwarded to argo-shim.
#
# Overridable via environment:
#   SESSION   tmux session name   (default: argo-shim, or argo-shim-tunnel with --tunnel)
#   ARGOVENV  path to the venv     (default: $HOME/argovenv)
#   SSH_KEY   private key to ssh-add (default: $HOME/.ssh/id_ed25519)

set -euo pipefail

ARGOVENV="${ARGOVENV:-$HOME/argovenv}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

# --all is handled entirely by the launcher, so strip it from the args before
# anything else looks at them. Whatever else you pass is forwarded to both.
ALL_MODE=false
_rest=()
for _arg in "$@"; do
  if [[ "$_arg" == "--all" ]]; then ALL_MODE=true; else _rest+=("$_arg"); fi
done
$ALL_MODE && set -- ${_rest[@]+"${_rest[@]}"}

# Session name defaults from the mode: --tunnel (anywhere in the args) selects
# the §7 tunnel instance, which runs in its own session so it can coexist with
# the regular shim. An explicit SESSION= always wins.
if [[ -z "${SESSION:-}" ]]; then
  SESSION="argo-shim"
  for _arg in "$@"; do
    [[ "$_arg" == "--tunnel" ]] && { SESSION="argo-shim-tunnel"; break; }
  done
fi

# Absolute path to this script, so tmux can re-exec it regardless of cwd.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---------- worker: runs inside the tmux session ----------
if [[ "${1:-}" == "__inner__" ]]; then
  shift  # drop the sentinel; remaining args become argo-shim's args
  args=("$@")

  # shellcheck disable=SC1091
  source "$ARGOVENV/bin/activate"

  # In --tunnel mode argo-shim requires --tunnel-port (it only auto-derives the
  # shim port). Compute it as shim_port + 1, using the same username->port
  # derivation argo-shim uses, unless the caller passed --tunnel-port already.
  want_tunnel=false
  have_tunnel_port=false
  if (( ${#args[@]} )); then
    for a in "${args[@]}"; do
      case "$a" in
        --tunnel) want_tunnel=true ;;
        --tunnel-port|--tunnel-port=*) have_tunnel_port=true ;;
      esac
    done
  fi
  if $want_tunnel && ! $have_tunnel_port; then
    tunnel_port="$(python - <<'PY'
import hashlib, getpass, os
u = os.environ.get("CELS_USERNAME", getpass.getuser())
shim = 10000 + (int(hashlib.sha256(u.encode()).hexdigest()[:8], 16) % 22768)
print(shim + 1)
PY
)"
    echo ">>> Derived --tunnel-port ${tunnel_port} (shim_port + 1) for this user."
    args+=(--tunnel-port "$tunnel_port")
  fi

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

  # Careful: don't print the literal success string here. --all greps this pane
  # to decide whether the shim came up, and would match this line instead.
  echo ">>> Starting argo-shim. Approve the Duo push, then wait for the green health-check line."
  echo ">>> When healthy, detach with:  Ctrl-b d   (argo-shim keeps running)"
  if (( ${#args[@]} )); then
    argo-shim "${args[@]}" || true
  else
    argo-shim || true
  fi

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

# Load the key here, in your own shell, so the passphrase is typed once no
# matter how many sessions we start. A tmux session inherits the environment of
# the tmux *server* (fixed when the server first started), not of the client
# creating the session, so a session started later never sees an agent set up
# inside an earlier one. We hand the agent over explicitly instead.
ensure_agent() {
  local rc=0
  ssh-add -l >/dev/null 2>&1 || rc=$?   # 0 = has keys, 1 = agent empty, 2 = no agent
  if [[ "$rc" -eq 2 ]]; then
    eval "$(ssh-agent -s)" >/dev/null
    rc=1
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo ">>> Adding SSH key ($SSH_KEY) — enter its passphrase when prompted:"
    ssh-add "$SSH_KEY"
  else
    echo ">>> SSH key already loaded in the agent — no passphrase needed."
  fi
}

# Build the command tmux should run, with the agent passed in via `env`. tmux
# joins its command arguments and runs them through sh, so everything is quoted.
# This works on any tmux version (the `-e` flag would need 3.2+, Bebop has 2.7).
tmux_cmd() {
  local out=(env)
  if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then out+=("SSH_AUTH_SOCK=$SSH_AUTH_SOCK"); fi
  if [[ -n "${SSH_AGENT_PID:-}" ]]; then out+=("SSH_AGENT_PID=$SSH_AGENT_PID"); fi
  out+=("$SELF" __inner__ "$@")
  printf '%q ' "${out[@]}"
}

# Poll a detached session's pane until `pattern` shows up. Returns 1 if the
# session died first, 2 on timeout. `-S -` reads the full scrollback, not just
# the visible screen, so a match can't be missed by scrolling off between polls.
wait_for() {
  local session="$1" ok_pat="$2" fail_pat="$3" limit="${4:-180}" waited=0 pane
  while (( waited < limit )); do
    tmux has-session -t "$session" 2>/dev/null || return 1
    pane="$(tmux capture-pane -p -S - -t "$session" 2>/dev/null || true)"
    grep -qE "$ok_pat"   <<<"$pane" && return 0
    # The worker keeps the pane open on a shell after argo-shim dies, so the
    # session staying alive is not evidence of success. Watch for the exit line.
    grep -qE "$fail_pat" <<<"$pane" && return 1
    sleep 2
    waited=$(( waited + 2 ))
  done
  return 2
}

# A detached session defaults to an 80-column pane, which wraps argo-shim's
# output mid-line and can split the strings we grep for. Give it room.
NEW_DETACHED=(tmux new-session -d -x 200 -y 50)

# ---------- --all: both sessions, sequentially ----------
if $ALL_MODE; then
  if tmux has-session -t argo-shim 2>/dev/null; then
    echo ">>> Session 'argo-shim' is already running — leaving it alone."
  else
    ensure_agent
    echo ">>> [1/2] Starting 'argo-shim'. Approve the Duo push, wait for"
    echo ">>>       '✅ All health checks passed', then detach with:  Ctrl-b d"
    "${NEW_DETACHED[@]}" -s argo-shim "$(tmux_cmd "$@")"
    tmux attach -t argo-shim
  fi

  tmux has-session -t argo-shim 2>/dev/null || {
    echo "error: 'argo-shim' is not running. Start it on its own to see why." >&2; exit 1; }

  if tmux has-session -t argo-shim-tunnel 2>/dev/null; then
    echo ">>> Session 'argo-shim-tunnel' is already running — nothing left to do."
    exit 0
  fi

  # The tunnel reuses what the first shim established, so it needs no input and
  # can come up detached. Sequential on purpose: running the two concurrently
  # races and can produce a second Duo prompt in a session you aren't watching.
  echo ">>> [2/2] Starting 'argo-shim-tunnel' in the background (no input needed)..."
  "${NEW_DETACHED[@]}" -s argo-shim-tunnel "$(tmux_cmd --tunnel "$@")"

  rc=0
  wait_for argo-shim-tunnel 'Tunnel created on port|health checks passed' 'argo-shim exited' 180 || rc=$?
  case "$rc" in
    1) echo "error: 'argo-shim-tunnel' exited while starting up." >&2
       echo "       Re-run as: $0 --tunnel   to watch it directly." >&2; exit 1 ;;
    2) echo "error: timed out waiting for the tunnel to report ready." >&2
       echo "       Inspect it with: tmux attach -t argo-shim-tunnel" >&2; exit 1 ;;
  esac
  tmux capture-pane -p -t argo-shim-tunnel | grep -E 'Derived port|Tunnel created on port' || true

  echo
  echo ">>> Both sessions are up. Attach with:"
  echo ">>>   tmux attach -t argo-shim          (login-node shim)"
  echo ">>>   tmux attach -t argo-shim-tunnel   (tunnel for compute nodes)"
  exit 0
fi

# ---------- single session ----------
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already exists — attaching (Ctrl-b d to detach)."
  exec tmux attach -t "$SESSION"
fi

ensure_agent
echo "Creating tmux session '$SESSION' and attaching..."
exec tmux new-session -s "$SESSION" "$(tmux_cmd "$@")"
