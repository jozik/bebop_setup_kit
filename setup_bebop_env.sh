#!/usr/bin/env bash
# Bebop user-space environment installer for .Rmd / .qmd / .ipynb workflows.
#
# Installs into the user's HOME:
#   ~/miniforge3/                  conda + R 4.5 + Python 3 + Jupyter + IRkernel + packages
#   ~/local/quarto-1.9.38/         Quarto
#   ~/.local/bin/{R,Rscript,quarto}  wrappers / symlinks
#   ~/.vscode-server/data/Machine/settings.json  (merged in; backed up first)
#   ~/miniforge3/share/jupyter/kernels/ir/kernel.json  (rewritten to absolute R path)
#
# Idempotent: re-running skips already-installed pieces.
# Safe: never runs `conda init`, never touches system paths, backs up files before edits.

set -euo pipefail

# ---------- pinned versions / URLs ----------
MINIFORGE_INSTALLER_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
QUARTO_VERSION="1.9.38"
QUARTO_URL="https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
VSCODE_EXTENSIONS=(reditorsupport.r quarto.quarto ms-toolsai.jupyter)

# Packages installed in one conda transaction. Always pass --override-channels.
CONDA_PACKAGES=(
  r-base r-svglite r-ragg r-cairo r-httpgd
  r-knitr r-rmarkdown r-languageserver r-irkernel
  r-data.table r-ggplot2 r-ggally r-foreach r-doparallel r-gridextra r-dplyr
  jupyter ipykernel numpy pandas matplotlib scipy
)

# ---------- paths ----------
MINIFORGE="$HOME/miniforge3"
LOCAL_PREFIX="$HOME/local"
QUARTO_DIR="$LOCAL_PREFIX/quarto-${QUARTO_VERSION}"
BIN="$HOME/.local/bin"

# Resolve the directory this script lives in (for merge_vscode_settings.py and test/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- helpers ----------
log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
step() { printf '\n=== %s ===\n' "$*"; }
die()  { printf '[error] %s\n' "$*" >&2; exit 1; }

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local b="${f}.bak.$(date +%s)"
  cp -p "$f" "$b"
  log "backed up $f -> $b"
}

# ---------- steps ----------
preflight() {
  step "Preflight"
  local fqdn arch
  fqdn=$(hostname -f 2>/dev/null || hostname)
  arch=$(uname -m)
  log "host: $fqdn   arch: $arch"
  case "$fqdn" in
    *.lcrc.anl.gov) ;;
    *) log "warning: hostname does not look like Bebop (.lcrc.anl.gov). Continuing anyway." ;;
  esac
  [[ "$arch" == "x86_64" ]] || die "Unsupported arch: $arch (this script targets x86_64)"
  mkdir -p "$BIN" "$LOCAL_PREFIX"
  case ":$PATH:" in
    *":$BIN:"*) ;;
    *) log "warning: $BIN is not on PATH. Add 'export PATH=\$HOME/.local/bin:\$PATH' to your shell profile." ;;
  esac
}

install_miniforge() {
  step "Miniforge3"
  if [[ -x "$MINIFORGE/bin/conda" ]]; then
    log "[skip] miniforge already at $MINIFORGE"
    return 0
  fi
  local tmp
  tmp=$(mktemp -t miniforge.XXXXXX.sh)
  log "downloading miniforge installer..."
  curl -fsSL -o "$tmp" "$MINIFORGE_INSTALLER_URL" || { rm -f "$tmp"; die "miniforge download failed"; }
  log "installing to $MINIFORGE (batch mode, no conda init)..."
  bash "$tmp" -b -p "$MINIFORGE" >/dev/null
  rm -f "$tmp"
  [[ -x "$MINIFORGE/bin/conda" ]] || die "miniforge install did not produce $MINIFORGE/bin/conda"
}

conda_install_packages() {
  step "Conda packages (R + Python + Jupyter + IRkernel)"
  local needed=()
  local installed
  installed=$("$MINIFORGE/bin/conda" list -n base 2>/dev/null | awk 'NR>3 {print $1}')
  for pkg in "${CONDA_PACKAGES[@]}"; do
    if grep -qx -- "$pkg" <<<"$installed"; then
      :
    else
      needed+=("$pkg")
    fi
  done
  if (( ${#needed[@]} == 0 )); then
    log "[skip] all ${#CONDA_PACKAGES[@]} packages already present"
    return 0
  fi
  log "installing ${#needed[@]} package(s): ${needed[*]}"
  # --override-channels is REQUIRED on this account: the pre-existing ~/.condarc
  # lists dead system channels (file:///soft/python/conda/conda-bld/,
  # http://repo.continuum.io/pkgs/free/linux-64/) which 404. Bypassing them by
  # forcing conda-forge avoids UnavailableInvalidChannel errors.
  "$MINIFORGE/bin/conda" install -n base -y \
    --override-channels -c conda-forge "${needed[@]}"
}

install_quarto() {
  step "Quarto $QUARTO_VERSION"
  if [[ -x "$QUARTO_DIR/bin/quarto" ]]; then
    log "[skip] quarto already at $QUARTO_DIR"
  else
    local tmp
    tmp=$(mktemp -t quarto.XXXXXX.tar.gz)
    log "downloading quarto tarball..."
    curl -fsSL -o "$tmp" "$QUARTO_URL" || { rm -f "$tmp"; die "quarto download failed"; }
    log "extracting to $LOCAL_PREFIX..."
    tar -xzf "$tmp" -C "$LOCAL_PREFIX"
    rm -f "$tmp"
    [[ -x "$QUARTO_DIR/bin/quarto" ]] || die "quarto extraction did not produce $QUARTO_DIR/bin/quarto"
  fi
  # symlink ~/.local/bin/quarto -> the versioned binary
  local link="$BIN/quarto"
  if [[ -L "$link" && "$(readlink "$link")" == "$QUARTO_DIR/bin/quarto" ]]; then
    log "[skip] $link symlink already correct"
  else
    [[ -e "$link" || -L "$link" ]] && backup_file "$link" && rm -f "$link"
    ln -s "$QUARTO_DIR/bin/quarto" "$link"
    log "symlinked $link -> $QUARTO_DIR/bin/quarto"
  fi
}

install_wrappers() {
  step "R wrappers (~/.local/bin/{R,Rscript})"
  local desired_r='#!/usr/bin/env bash
exec $HOME/miniforge3/bin/R "$@"
'
  local desired_rscript='#!/usr/bin/env bash
exec $HOME/miniforge3/bin/Rscript "$@"
'
  install_wrapper "$BIN/R" "$desired_r"
  install_wrapper "$BIN/Rscript" "$desired_rscript"
}

install_wrapper() {
  local path="$1" desired="$2"
  # `$(cat …)` strips trailing newlines; compare via cmp against a process
  # substitution to handle the trailing newline correctly.
  if [[ -f "$path" ]] && cmp -s "$path" <(printf '%s' "$desired"); then
    log "[skip] $path already correct"
    return 0
  fi
  backup_file "$path"
  printf '%s' "$desired" > "$path"
  chmod +x "$path"
  log "wrote $path"
}

fix_irkernel_kernelspec() {
  step "IRkernel kernelspec (absolute R path)"
  local spec="$MINIFORGE/share/jupyter/kernels/ir/kernel.json"
  [[ -f "$spec" ]] || die "IRkernel kernelspec missing at $spec (did the r-irkernel install run?)"
  local desired_r="$MINIFORGE/bin/R"
  # Use the conda python to parse + rewrite the JSON safely.
  "$MINIFORGE/bin/python" - "$spec" "$desired_r" <<'PY'
import json, shutil, sys, time
spec_path, desired_r = sys.argv[1], sys.argv[2]
with open(spec_path) as f:
    spec = json.load(f)
argv = spec.get("argv", [])
if argv and argv[0] == desired_r:
    print(f"[skip] {spec_path} already pinned to {desired_r}")
    raise SystemExit(0)
backup = f"{spec_path}.bak.{int(time.time())}"
shutil.copy2(spec_path, backup)
print(f"[backup] {backup}")
spec["argv"] = [desired_r] + argv[1:] if argv else [desired_r, "--slave", "-e", "IRkernel::main()", "--args", "{connection_file}"]
with open(spec_path, "w") as f:
    json.dump(spec, f)
    f.write("\n")
print(f"[wrote]  {spec_path}")
PY
}

merge_vscode_settings() {
  step "VSCode Machine settings.json"
  "$MINIFORGE/bin/python" "$SCRIPT_DIR/merge_vscode_settings.py"
}

install_vscode_extensions() {
  step "VSCode extensions (Remote-SSH host)"
  local code_cli
  code_cli=$(find "$HOME/.vscode-server/bin" -maxdepth 3 -path '*/bin/remote-cli/code' 2>/dev/null | sort | tail -1)
  if [[ -z "$code_cli" ]]; then
    log "[warn] no VSCode remote CLI found under ~/.vscode-server/bin/*/bin/remote-cli/code"
    log "       This is expected if you've never opened VSCode Remote-SSH on this host yet."
    log "       After connecting once, re-run this script (or install extensions from the VSCode UI):"
    for ext in "${VSCODE_EXTENSIONS[@]}"; do log "         $ext"; done
    return 0
  fi
  log "using code CLI: $code_cli"
  local installed
  installed=$("$code_cli" --list-extensions 2>/dev/null || true)
  for ext in "${VSCODE_EXTENSIONS[@]}"; do
    if grep -qix -- "$ext" <<<"$installed"; then
      log "[skip] $ext already installed"
    else
      log "installing $ext..."
      "$code_cli" --install-extension "$ext" >/dev/null
    fi
  done
}

run_smoke_tests() {
  step "Smoke tests"
  local test_dir="$SCRIPT_DIR/test"
  [[ -d "$test_dir" ]] || { log "[warn] no $test_dir directory; skipping smoke tests"; return 0; }
  local tmp
  tmp=$(mktemp -d -t smoke.XXXXXX)
  local pass=0 fail=0

  for f in smoke.qmd smoke.Rmd; do
    if [[ -f "$test_dir/$f" ]]; then
      cp "$test_dir/$f" "$tmp/"
      if (cd "$tmp" && "$BIN/quarto" render "$f" >/dev/null 2>&1); then
        log "[pass] quarto render $f"
        pass=$((pass + 1))
      else
        log "[fail] quarto render $f"
        fail=$((fail + 1))
      fi
    fi
  done

  # smoke.ipynb is a user-facing notebook with both Python and R cells; the user
  # is expected to switch the kernel in VSCode and re-run. `nbconvert --execute`
  # runs every cell with the kernel pinned in metadata, so we can't headless-run
  # the full file. Instead, fabricate a tiny one-cell notebook per kernel.
  local py_nb="$tmp/smoke_py.ipynb"
  cat > "$py_nb" <<'JSON'
{"cells":[{"cell_type":"code","metadata":{},"source":"import sys, numpy, pandas, matplotlib\nprint('python', sys.version.split()[0])","outputs":[],"execution_count":null,"id":"a"}],
 "metadata":{"kernelspec":{"display_name":"Python 3","language":"python","name":"python3"}},
 "nbformat":4,"nbformat_minor":5}
JSON
  if (cd "$tmp" && "$MINIFORGE/bin/jupyter" nbconvert --to notebook --execute smoke_py.ipynb --output smoke_py_out.ipynb >/dev/null 2>&1); then
    log "[pass] jupyter nbconvert --execute (Python kernel)"
    pass=$((pass + 1))
  else
    log "[fail] jupyter nbconvert --execute (Python kernel)"
    fail=$((fail + 1))
  fi

  local r_nb="$tmp/smoke_r.ipynb"
  cat > "$r_nb" <<'JSON'
{"cells":[{"cell_type":"code","metadata":{},"source":"cat('R smoke ok:', R.version.string, '\\n')","outputs":[],"execution_count":null,"id":"a"}],
 "metadata":{"kernelspec":{"display_name":"R","language":"R","name":"ir"}},
 "nbformat":4,"nbformat_minor":5}
JSON
  if (cd "$tmp" && "$MINIFORGE/bin/jupyter" nbconvert --to notebook --execute smoke_r.ipynb --output smoke_r_out.ipynb >/dev/null 2>&1); then
    log "[pass] jupyter nbconvert --execute (R kernel)"
    pass=$((pass + 1))
  else
    log "[fail] jupyter nbconvert --execute (R kernel)"
    fail=$((fail + 1))
  fi

  rm -rf "$tmp"
  log "smoke tests: ${pass} passed, ${fail} failed"
  (( fail == 0 )) || die "one or more smoke tests failed"
}

final_message() {
  step "Done"
  cat <<'EOF'
The shell-side install is complete. To verify the GUI workflows:

  1. Open VSCode locally, connect Remote-SSH to bebop.
  2. Reload the window (Cmd/Ctrl+Shift+P -> "Developer: Reload Window").
  3. Open the test/ directory and follow SETUP.md section "Verify in VSCode".

If any extension install was deferred (e.g. no VSCode remote CLI yet), re-run
this script after your first Remote-SSH connection.
EOF
}

main() {
  preflight
  install_miniforge
  conda_install_packages
  install_quarto
  install_wrappers
  fix_irkernel_kernelspec
  merge_vscode_settings
  install_vscode_extensions
  run_smoke_tests
  final_message
}

main "$@"
