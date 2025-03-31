#!/usr/bin/env bash
pod="$1"
fail() {
  echo "$@" 1>&2
  exit 1
}
# https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-conditions
get_condition_time() {
  condition="$1"
  iso_time=$(kubectl get pod "$pod" -o json | jq ".status.conditions[] | select(.type == \"$condition\" and .status == \"True\") | .lastTransitionTime" | tr -d '"\n')
  test -n "$iso_time" || fail "Pod $pod is not in $condition yet"
  if [[ "$(uname)" == "Darwin" ]]; then
      date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_time" +%s
  elif [[ "$(uname)" == "Linux" ]]; then
      date -d $iso_time +%s
  fi
}
initialized_time=$(get_condition_time PodScheduled)
ready_time=$(get_condition_time Ready)
duration_seconds=$(( ready_time - initialized_time ))
OS=$(uname)
echo "It took approximately $duration_seconds seconds for $pod to boot up and this script is ran on $OS operating system"
