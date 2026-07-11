# Bebop Setup Kit

A collection of user-space setup kits for working on Argonne's LCRC **Bebop** cluster:
development environments, VSCode Remote-SSH workflows, and running Claude Code against
Argonne GCE resources via `argo-shim`.

On Bebop the kit lives in the shared EMEWS project space, so you can use it in place —
**no clone required**:

```
/lcrc/project/EMEWS/bebop_setup_kit
```

Off Bebop, or to keep your own copy, clone it:

```bash
git clone https://github.com/jozik/bebop_setup_kit.git
```

## Contents

| Directory | What it's for |
| --- | --- |
| [`r-quarto-jupyter/`](r-quarto-jupyter/) | User-space R 4.5 + Python + Quarto + Jupyter environment wired up to VSCode Remote-SSH for `.Rmd` / `.qmd` / `.ipynb` workflows. Start with its [README](r-quarto-jupyter/README.md) / [SETUP](r-quarto-jupyter/SETUP.md). |
| [`claude-on-lcrc/`](claude-on-lcrc/) | Guide for running Claude Code (CLI + VSCode plugin) on Bebop via `argo-shim`, including the compute-node tunnel workflow. See [claude-on-lcrc.md](claude-on-lcrc/claude-on-lcrc.md). Includes [`start-argo-shim.sh`](claude-on-lcrc/start-argo-shim.sh) to launch `argo-shim` (or `--tunnel`) in a tmux session in one step. |
| [`agent-bits/`](agent-bits/) | Batch scripts (`argo-shim.qsub` + `submit-argo-shim.sh`) to run `argo-shim` on a Bebop compute node. See its [README](agent-bits/README.md). |

## Questions

jozik@anl.gov
