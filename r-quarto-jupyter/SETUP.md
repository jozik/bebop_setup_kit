# Bebop setup for `.Rmd` / `.qmd` / `.ipynb` workflows

This walkthrough installs a working R + Python + Quarto + Jupyter environment in your
Bebop home directory and wires it up to VSCode Remote-SSH so that you can:

- Author and render `.Rmd` and `.qmd` files (Quarto, knitr engine, inline plots in VSCode)
- Author and run `.ipynb` notebooks with Python *or* R kernels
- Use the REditorSupport R extension's **Workspace Viewer** and **httpgd plot panel**

Time: ~15 minutes the first time (mostly conda download/install). Re-running is a no-op.

---

## 1. Prerequisites

- **VSCode** installed locally with the **Remote-SSH** extension
  (`ms-vscode-remote.remote-ssh`).
- An **SSH config entry for Bebop** that already works. You should be able to do
  `ssh bebop` and land on a Bebop login or interactive node without typing a password.
- `~/.local/bin` on your shell `PATH`. Most setups already do this; if not, add
  `export PATH="$HOME/.local/bin:$PATH"` to your `~/.bashrc`.

---

## 2. Run the installer

From inside an SSH session on Bebop (a plain `ssh bebop` terminal is fine, you don't
need VSCode yet). The kit is already in the shared EMEWS project space, so you can run
it in place — the installer only writes to your `$HOME`:

```bash
cd /lcrc/project/EMEWS/bebop_setup_kit/r-quarto-jupyter
bash setup_bebop_env.sh
```

Off Bebop, or to keep your own copy, clone it instead:

```bash
git clone https://github.com/jozik/bebop_setup_kit.git ~/bebop_setup_kit
cd ~/bebop_setup_kit/r-quarto-jupyter
bash setup_bebop_env.sh
```

What it does, in order:

1. **Preflight** — verifies the host is Bebop and architecture is x86_64.
2. **Miniforge3** — downloads and installs to `~/miniforge3` (skips if already there).
   Does **not** run `conda init` — your shell is left alone.
3. **Conda packages** — installs R 4.5 + graphics stack + Python 3 + Jupyter +
   IRkernel + the package set commonly used for analyses, all into the conda **base**
   env. Always uses `--override-channels -c conda-forge` (see Troubleshooting §5).
4. **Quarto 1.9.38** — downloads the prebuilt tarball to `~/local/quarto-1.9.38/`
   and symlinks `~/.local/bin/quarto`.
5. **R wrappers** — writes `~/.local/bin/R` and `~/.local/bin/Rscript` that exec
   into the conda R. Existing files (if any) are backed up to `.bak.<timestamp>`.
6. **IRkernel kernelspec** — pins the `ir` kernel to the absolute conda-R path so
   the VSCode Jupyter extension launches the right R.
7. **VSCode Machine settings** — merges seven R/Quarto keys into
   `~/.vscode-server/data/Machine/settings.json` (file backed up first; existing keys
   preserved).
8. **VSCode extensions** — installs `reditorsupport.r`, `quarto.quarto`,
   `ms-toolsai.jupyter` on the remote.
   *If you have never opened VSCode Remote-SSH to Bebop yet*, the script will print
   a warning and skip this step — re-run after your first connection.
9. **Smoke tests** — headless-renders `test/smoke.qmd`, `test/smoke.Rmd`, and
   executes `test/smoke.ipynb` with both kernels. Output is "[pass]" / "[fail]" per
   test; the script exits nonzero if any failed.
10. **Done** — prints next-step instructions.

The script is **idempotent**: re-running it skips anything already installed. Safe to
re-run after a partial failure or after updates to this kit.

---

## 3. Verify in VSCode

Open VSCode locally → **Remote-SSH: Connect to Host…** → `bebop`. Open the
`/lcrc/project/EMEWS/bebop_setup_kit/r-quarto-jupyter/test/` folder (or
`~/bebop_setup_kit/r-quarto-jupyter/test/` if you cloned your own copy).

**Important first step:** **Reload the window**
(`Cmd/Ctrl+Shift+P` → `Developer: Reload Window`). The freshly-installed
extensions don't activate until VSCode reloads.

### 3a. `.qmd` workflow

1. Open `test/smoke.qmd`.
2. Open the Command Palette (`Cmd/Ctrl+Shift+P`) → **`R: Create R Terminal`**.
   A new terminal opens running R; this is **critical** — running R from a generic
   bash terminal does not enable the Workspace Viewer (see Cheat sheet below).
3. Click anywhere inside the R code chunk. You should see a small **"Run Cell"**
   code-lens link above the chunk (provided by the Quarto extension).
4. Click **Run Cell** (keybinding: `Cmd/Ctrl+Shift+Enter`).
5. The chunk text gets pasted into the R terminal; the ggplot output appears in an
   in-VSCode **Plot Viewer** tab (powered by `httpgd`), not a separate window.
6. Click the **R icon** in the left activity bar to open the **Workspace Viewer**.
   Assign a variable in the R terminal (e.g. `x <- 1:10`) and watch the panel
   populate. Click a data frame to open the data viewer.

### 3b. `.Rmd` workflow

Identical to `.qmd`. Open `test/smoke.Rmd` and repeat the steps above. Quarto's
knitr engine handles both file types; the YAML header syntax differs slightly
between them but everything else is the same.

### 3c. `.ipynb` workflow

1. Open `test/smoke.ipynb`. VSCode's notebook editor opens.
2. Look at the **top-right corner**: a kernel picker labeled "Select Kernel" or
   showing the current kernel. Click it; you should see at least:
   - **Python 3 (ipykernel)** → `~/miniforge3/bin/python`
   - **R** → `~/miniforge3/bin/R`
3. Pick **Python 3 (ipykernel)**.
4. Click into the first Python cell, run with **Shift+Enter** (run + advance) or
   **Ctrl+Enter** (run in place). The plot renders inline in the cell output.
5. To exercise the R cells, click the kernel picker again → **R**. This *restarts*
   the kernel (variables don't carry over). Scroll down to the R cells and run them.

---

## 4. Daily-use cheat sheet

**`.qmd` / `.Rmd` in VSCode:**

- **Always launch R via `R: Create R Terminal`** from the Command Palette. This is
  the *only* way the REditorSupport extension activates the session-watcher — running
  `R` from a bash terminal gives you a working REPL but an empty Workspace Viewer.
- **Run Cell sends to the active terminal.** If a bash terminal is the focused
  terminal, your R code goes there. Click the R terminal tab first.
- Reuse the same R terminal for the whole VSCode window. Only one is needed.

**`.ipynb`:**

- Switching the kernel **restarts execution** (variables lost). To work on Python
  and R together against shared data, prefer `.qmd` over `.ipynb`.
- The **VSCode Jupyter Variables panel does not support R** (it's an
  extension-level limitation, not a config issue). For R, use inline idioms:
  ```r
  ls()
  ls.str()
  str(x); summary(x); head(df)
  ```
  Or the `.env_summary()` snippet shown in the last cell of `smoke.ipynb` — re-run
  it any time for a name/class/size table of your global env.

**Adding R or Python packages later:**

```bash
~/miniforge3/bin/conda install -n base --override-channels -c conda-forge <pkg>
```

The `--override-channels` is required on Bebop accounts (see Troubleshooting §5).

For Python packages not available on conda-forge:

```bash
~/miniforge3/bin/pip install <pkg>
```

For R packages not on conda-forge: open R, then `install.packages("<pkg>")`. The
conda R has full graphics + libxml2 so most R packages should build.

---

## 5. Troubleshooting

### `UnavailableInvalidChannel: HTTP 404 ... /soft/python/conda/conda-bld`

Your account's `~/.condarc` lists dead system channels. The setup script bypasses
them with `--override-channels`. If you run `conda install` by hand and hit this,
add the same flag:

```bash
~/miniforge3/bin/conda install -n base --override-channels -c conda-forge <pkg>
```

Do **not** edit `~/.condarc` to "fix" this — it may have other settings you rely on.

### "Run Cell" sends my R code to a bash terminal

Click the R terminal tab to make it the *active* terminal, then run again. This is
because the `r.alwaysUseActiveTerminal: true` setting (which we want, for other
reasons) makes Run Cell follow whichever terminal is focused.

### Workspace Viewer is empty even though I'm in R

You launched R from a bash terminal instead of via `R: Create R Terminal`. Close
that terminal and use the Command Palette command. In a fresh R terminal,
`Sys.getenv("VSCODE_WATCHER_DIR")` should print a path (not `""`); if it's empty,
the session watcher isn't active.

### ggplot opens in a browser tab instead of the VSCode plot panel

`r.plot.useHttpgd` isn't taking effect. Check
`~/.vscode-server/data/Machine/settings.json` (not your local User settings) — the
setup script writes it there because VSCode Remote-SSH ignores local User settings
for `r.plot.*`. Re-run `setup_bebop_env.sh` to re-merge.

### `quarto preview` doesn't refresh when I save

`quarto.render.renderOnSave: true` must be in **Machine** settings (the
setup script handles this). The Quarto extension hardcodes `--no-watch-inputs`
on `quarto preview`, so saves only trigger re-renders when the extension is
explicitly told to do so via this setting.

### VSCode doesn't see new extensions or my new R wrapper

Reload the VSCode window: `Cmd/Ctrl+Shift+P` → `Developer: Reload Window`.

### The setup script printed "no VSCode remote CLI found"

You haven't connected to Bebop via VSCode Remote-SSH yet. Connect once, then
re-run `bash setup_bebop_env.sh` — it will find the CLI and finish the extension
install.

### One of the smoke tests failed

Read the script's preceding output to see which step failed. Most causes:

- Conda transaction was interrupted — re-run the script.
- VSCode Machine settings.json was hand-edited into invalid JSON — fix or delete
  it (script will recreate), then re-run.
- An R or Python package failed to install — check the conda step's output for
  the actual error and rerun.

---

## 6. What got installed where

| Path | What it is |
| --- | --- |
| `~/miniforge3/` | conda + R 4.5 + Python 3 + Jupyter + IRkernel + packages |
| `~/local/quarto-1.9.38/` | Quarto distribution |
| `~/.local/bin/R`, `~/.local/bin/Rscript` | wrappers that exec the conda R |
| `~/.local/bin/quarto` | symlink to `~/local/quarto-1.9.38/bin/quarto` |
| `~/.vscode-server/data/Machine/settings.json` | R/Quarto VSCode keys (merged, backed up) |
| `~/miniforge3/share/jupyter/kernels/{python3,ir}/kernel.json` | Jupyter kernelspecs |

Nothing system-wide is touched. Removing `~/miniforge3`, `~/local/quarto-*`, the
wrappers in `~/.local/bin/`, and the seven keys from settings.json fully reverses
the install.

---

## 7. Questions / issues

Email jozik@anl.gov.
