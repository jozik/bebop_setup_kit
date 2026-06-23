#!/bin/bash
# Submit argo-shim.qsub, wait for it to start, and print the DIS condo node.
#
# Usage: submit-argo-shim.sh <login-node-host>
#   <login-node-host> is the Bebop login node running your tunneled argo-shim,
#   i.e. beboplogin<N>.lcrc.anl.gov (N = 1..5). It is passed to the job as
#   TUNNEL_HOST so the compute-node argo-shim tunnels back to the right place.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOGIN_NODE="${1:-}"
if [[ -z "${LOGIN_NODE}" ]]; then
    echo "usage: $(basename "$0") <login-node-host>" >&2
    echo "  e.g. $(basename "$0") beboplogin5.lcrc.anl.gov" >&2
    exit 2
fi

JOBNAME="argo-shim-compute"

# Don't submit a second shim if one is already queued or running for this user.
# qselect matches the full Job_Name (qstat truncates it). -s RQ = running/queued.
EXISTING="$(qselect -u "${USER}" -N "${JOBNAME}" -s RQ 2>/dev/null || true)"
if [[ -n "${EXISTING}" ]]; then
    echo "An argo-shim compute job is already queued/running for ${USER}:"
    for jid in ${EXISTING}; do
        qstat "${jid}" 2>/dev/null | tail -n +3 || echo "  ${jid}"
    done
    echo "Not submitting another. Use 'qdel <jobid>' first if you want to replace it."
    exit 0
fi

JOBID="$(qsub -v TUNNEL_HOST="${LOGIN_NODE}" "${SCRIPT_DIR}/argo-shim.qsub")"
echo "submitted ${JOBID} (tunnel host: ${LOGIN_NODE})"

# Poll until PBS assigns a node (job enters the R state).
printf "waiting for node"
while :; do
    STATE="$(qstat -f "${JOBID}" | awk -F'= ' '/job_state/{print $2}')"
    if [[ "${STATE}" == "R" ]]; then
        break
    fi
    printf "."
    sleep 5
done
echo

NODE="$(qstat -f "${JOBID}" | awk -F'= ' '/exec_host/{split($2,a,"/"); print a[1]}')"
echo "argo-shim node: ${NODE}"
