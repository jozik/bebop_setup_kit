# agent-bits

Batch scripts for running `argo-shim` on a Bebop **compute node**, so you can use
Claude Code on a compute node tunneled through a login-node `argo-shim`. See
[`../claude-on-lcrc/claude-on-lcrc.md`](../claude-on-lcrc/claude-on-lcrc.md) §7 for the
full workflow.

## Files

- [`argo-shim.qsub`](argo-shim.qsub) — PBS batch job: requests a DIS condo node, loads
  the `argovenv` environment, derives the per-user argo-shim ports, and launches
  `argo-shim` pointed at your login-node tunnel. The login node comes from the
  `TUNNEL_HOST` environment variable (no hardcoded host).
- [`submit-argo-shim.sh`](submit-argo-shim.sh) — wrapper that submits the job, refuses to
  start a second one if you already have one queued/running, waits for it to schedule, and
  prints the compute node it landed on.

## Usage

From any Bebop login node, pass the login node where your tunneled `argo-shim` is running
(`beboplogin<N>.lcrc.anl.gov`, N = 1..5):

E.g., if `argo-shim` is running on `beboplogin1.lcrc.anl.gov`
```bash
/lcrc/project/EMEWS/bebop_setup_kit/agent-bits/submit-argo-shim.sh beboplogin1.lcrc.anl.gov
```

The script is location-independent (it finds `argo-shim.qsub` next to itself), so you can
run it straight from the shared path above without cloning.

To submit the job by hand instead of using the wrapper:

```bash
qsub -v TUNNEL_HOST=beboplogin1.lcrc.anl.gov argo-shim.qsub
```