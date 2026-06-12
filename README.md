# bebop_setup_kit

User-space setup for working with `.Rmd`, `.qmd`, and `.ipynb` files on
Argonne's Bebop cluster via VSCode Remote-SSH.

Installs into your `$HOME` only — no admin required:

- conda-forge R 4.5 with full graphics stack (Cairo, png, svglite, ragg, httpgd)
- Python 3 + Jupyter + IRkernel
- Quarto 1.9.38 (renders both `.qmd` and `.Rmd`)
- VSCode Machine settings + extensions (`reditorsupport.r`, `quarto.quarto`,
  `ms-toolsai.jupyter`) for inline plots, Workspace Viewer, kernel pickers

## Quick start

```bash
ssh bebop
git clone https://github.com/jozik/bebop_setup_kit.git ~/bebop_setup_kit
cd ~/bebop_setup_kit
bash setup_bebop_env.sh
```

Then open VSCode locally → Remote-SSH to `bebop` → reload window → follow
[SETUP.md §3](SETUP.md#3-verify-in-vscode) to verify the GUI workflows.

## Files

- [`SETUP.md`](SETUP.md) — full walkthrough (prerequisites, install, VSCode
  verification, daily cheat sheet, troubleshooting)
- [`setup_bebop_env.sh`](setup_bebop_env.sh) — idempotent shell installer
- [`merge_vscode_settings.py`](merge_vscode_settings.py) — JSON merger for
  `~/.vscode-server/data/Machine/settings.json` (invoked by the shell script)
- [`test/`](test/) — `smoke.qmd`, `smoke.Rmd`, `smoke.ipynb` for verifying
  the install end-to-end

## Questions

jozik@anl.gov
