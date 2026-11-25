#!/usr/bin/env bash
# Creates the OCC Namespace that isolates this sample (its own IAM scope, Secrets,
# credential sources and Kubernetes namespace), waits until it is ready, and
# prints its ID. Run once; a Namespace name stays reserved even after deletion.
#
#   OCC_URL=... OCC_SERVICE_KEY_FILE=... ./namespace.sh
set -euo pipefail                                  # stop on the first failing command or unset variable
: "${OCC_URL:?}" "${OCC_SERVICE_KEY_FILE:?}"       # require the OCC endpoint and the service-key file
OCC=${OCC:-occ}                                    # the occ binary to run; override with OCC=/path/to/occ
NAMESPACE_NAME=${NAMESPACE_NAME:-review-wait}     # the Namespace's human name (not its ID)

id=$($OCC namespace create "$NAMESPACE_NAME" -o json | jq -er .id)   # ask OCC for the Namespace; keep the server-assigned ID
echo "Namespace $id: waiting for it to become ready..." >&2          # the worker provisions it in the background
for _ in $(seq 1 60); do                                             # poll for up to 5 minutes
  status=$($OCC namespace get "$id" -o json | jq -er .status)        # read provisioning, ready or failed
  case "$status" in
    ready) printf '%s\n' "$id"; exit 0 ;;                            # ready: print the ID for the next scripts
    failed) echo "Namespace $id failed; check the worker's namespace.ensure logs" >&2; exit 1 ;;  # failed is final
  esac
  sleep 5                                                            # still provisioning: wait and read again
done
echo "Timed out; last status: $status" >&2                           # never reached ready within the wait
exit 1
