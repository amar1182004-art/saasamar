#!/bin/sh
set -eu

wait_for() {
  name="$1"
  url="$2"
  attempts="${3:-60}"

  i=1
  while [ "$i" -le "$attempts" ]; do
    if curl --fail --silent --show-error "$url" >/dev/null; then
      echo "$name is ready"
      return 0
    fi

    sleep 2
    i=$((i + 1))
  done

  echo "$name did not become ready: $url" >&2
  return 1
}

wait_for "Web health" "http://127.0.0.1:3000/api/health"
wait_for "API health" "http://127.0.0.1:3001/health"
wait_for "AI health" "http://127.0.0.1:8000/health"
wait_for "API readiness" "http://127.0.0.1:3001/ready"
wait_for "Web readiness" "http://127.0.0.1:3000/api/ready"
wait_for "AI readiness" "http://127.0.0.1:8000/ready"

echo "Crystell smoke checks passed"
