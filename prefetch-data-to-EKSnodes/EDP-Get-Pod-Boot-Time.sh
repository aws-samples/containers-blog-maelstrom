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
  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_time" +%s # Enable this line if you are running on Mac terminal
  #date -d $iso_time +%s # Enable this line if you are running on Linux terminal
}
initialized_time=$(get_condition_time PodScheduled)
ready_time=$(get_condition_time Ready)
duration_seconds=$(( ready_time - initialized_time ))
echo "It took $duration_seconds seconds for $pod to boot up"
