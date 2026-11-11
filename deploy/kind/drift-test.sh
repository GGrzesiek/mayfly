#!/usr/bin/env bash
# Measures how long Argo CD takes to undo manual changes on the kind cluster.
#
# Scenarios, ROUNDS times each:
#   modify  change a field git manages (APP_ENV on the flask-app Deployment)
#           and wait until it reads the git value again
#   delete  delete the flask-app Service and wait until a new one exists
#
# Modes:
#   isolated  (default) a manual sync before every round, so each drift is
#             timed as a first offence. Both scenarios.
#   repeated  drift again as soon as the last one is reverted, no reset.
#             `modify` only. Shows Argo CD's self-heal backoff: from the
#             second attempt on, each self-heal waits longer (2s, x3 per
#             attempt, capped at 300s by default), and only a sync that is
#             not a self-heal resets the count.
#
# Each round is timed from just before the drifting kubectl call to the first
# poll that sees the cluster match git again. A poll is one `kubectl get`
# (~170 ms against kind) plus POLL seconds, so the numbers run up to ~0.3 s
# high at the default POLL.
#
# Self-heal only covers fields the Application manages: a field that git never
# sets (an extra annotation, say) is not drift to Argo CD and stays put.
#
# Usage: drift-test.sh <kube-context> <rounds> <csv-out> [isolated|repeated]
set -euo pipefail

CONTEXT=${1:?kube context}
ROUNDS=${2:-5}
OUT=${3:?csv output path}
MODE=${4:-isolated}
POLL=${POLL:-0.1}
TIMEOUT=${TIMEOUT:-400}
NS=flask-app

k() { kubectl --context "$CONTEXT" "$@"; }

now_ms() { date +%s%3N; }

app_env() {
  k -n "$NS" get deploy flask-app \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="APP_ENV")].value}'
}

svc_uid() { k -n "$NS" get svc flask-app -o jsonpath='{.metadata.uid}' 2>/dev/null || true; }

app_field() { k -n argocd get application flask-app -o jsonpath="$1"; }

synced_healthy() {
  [ "$(app_field '{.status.sync.status}/{.status.health.status}')" = Synced/Healthy ]
}

# Waits until "$@" succeeds; prints elapsed ms since $1, or fails on timeout.
wait_until() {
  local start=$1; shift
  local deadline=$(( start + TIMEOUT * 1000 ))
  until "$@"; do
    if [ "$(now_ms)" -ge "$deadline" ]; then
      echo "timed out after ${TIMEOUT}s" >&2
      return 1
    fi
    sleep "$POLL"
  done
  echo $(( $(now_ms) - start ))
}

# Rounds start from a clean state, so one slow revert cannot leak into the
# next measurement.
wait_settled() {
  wait_until "$(now_ms)" synced_healthy >/dev/null
  k -n "$NS" rollout status deploy/flask-app --timeout="${TIMEOUT}s" >/dev/null
}

# A sync not started by self-heal resets the self-heal attempt count, and with
# it the backoff. The same thing `argocd app sync` does, without the CLI.
SYNC_ID=0
reset_backoff() {
  SYNC_ID=$(( SYNC_ID + 1 ))
  local user="drift-test-$$-$SYNC_ID" rev
  rev=$(app_field '{.status.sync.revision}')
  k -n argocd patch application flask-app --type merge -p \
    "{\"operation\":{\"initiatedBy\":{\"username\":\"$user\"},\"sync\":{\"revision\":\"$rev\"}}}" >/dev/null
  SYNC_DONE="Succeeded/$user"
  wait_until "$(now_ms)" sync_finished >/dev/null
}
sync_finished() {
  [ "$(app_field '{.status.operationState.phase}/{.status.operationState.operation.initiatedBy.username}')" = "$SYNC_DONE" ]
}

WANT_ENV=$(app_env)
[ -n "$WANT_ENV" ] || { echo "APP_ENV not found on deploy/flask-app" >&2; exit 1; }
synced_healthy \
  || { echo "flask-app is not Synced/Healthy; fix that first" >&2; exit 1; }

env_restored() { [ "$(app_env)" = "$WANT_ENV" ]; }

svc_replaced() {
  local uid
  uid=$(svc_uid)
  [ -n "$uid" ] && [ "$uid" != "$OLD_UID" ]
}

drift_modify() {
  local start ms
  start=$(now_ms)
  k -n "$NS" set env deploy/flask-app "APP_ENV=drift-$1" >/dev/null
  ms=$(wait_until "$start" env_restored)
  echo "modify,$MODE,$1,$ms" | tee -a "$OUT"
}

drift_delete() {
  local start ms
  OLD_UID=$(svc_uid)
  start=$(now_ms)
  k -n "$NS" delete svc flask-app --wait=false >/dev/null
  ms=$(wait_until "$start" svc_replaced)
  echo "delete,$MODE,$1,$ms" | tee -a "$OUT"
}

mkdir -p "$(dirname "$OUT")"
echo "scenario,mode,round,revert_ms" > "$OUT"

case "$MODE" in
  isolated)
    for round in $(seq 1 "$ROUNDS"); do
      wait_settled; reset_backoff
      drift_modify "$round"
      wait_settled; reset_backoff
      drift_delete "$round"
    done
    ;;
  repeated)
    wait_settled; reset_backoff
    for round in $(seq 1 "$ROUNDS"); do
      # No rollout wait here: the point is to drift again straight away.
      drift_modify "$round"
    done
    ;;
  *)
    echo "unknown mode: $MODE (isolated|repeated)" >&2; exit 1 ;;
esac

wait_settled
reset_backoff

# min / median / max per scenario, in seconds.
awk -F, 'NR > 1 { v[$1] = v[$1] " " $4 }
  END {
    for (s in v) {
      n = split(substr(v[s], 2), a, " ")
      for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] + 0 < a[i] + 0) { t = a[i]; a[i] = a[j]; a[j] = t }
      med = (n % 2) ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
      printf "%-7s n=%d  min %.1fs  median %.1fs  max %.1fs\n", s, n, a[1] / 1000, med / 1000, a[n] / 1000
    }
  }' "$OUT"
