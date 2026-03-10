#!/bin/bash

# Copyright The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

WORKER=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
NPD_POD=$(kubectl get pods -n kube-system -l component=staticpods-monitor --field-selector spec.nodeName=$WORKER -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

echo "=== Static Pods Readiness Verification ==="
echo ""

# NPD Status
NPD_READY=$(kubectl get ds -n kube-system node-problem-detector-staticpods -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}' 2>/dev/null || echo "0/0")
echo "NPD DaemonSet: $NPD_READY"

# NRR Status  
NRR=$(kubectl get nodereadinessrule static-pods-readiness-rule -o name 2>/dev/null || echo "not-deployed")
echo "NodeReadinessRule: $NRR"

echo ""
echo "Node: $WORKER"

# Manifests
MANIFESTS=$(kubectl exec -n kube-system $NPD_POD -- find /etc/kubernetes/manifests -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) 2>/dev/null | wc -l)
echo "  Manifests: $MANIFESTS"

# Mirror pods
MIRRORS=$(kubectl get pods --all-namespaces --field-selector spec.nodeName=$WORKER -o json | jq -r '.items[] | select(.metadata.ownerReferences[]?.kind == "Node") | .metadata.name' 2>/dev/null)
MIRROR_COUNT=$(echo "$MIRRORS" | grep -c . 2>/dev/null || echo "0")
echo "  Mirrors: $MIRROR_COUNT"
[ -n "$MIRRORS" ] && echo "$MIRRORS" | sed 's/^/    /'

# Condition
COND=$(kubectl get node $WORKER -o jsonpath='{.status.conditions[?(@.type=="StaticPodsMissing")]}' | jq -r '.status + " (" + .reason + ")"' 2>/dev/null || echo "not-set")
echo "  StaticPodsMissing: $COND"

# Taint
TAINT=$(kubectl get node $WORKER -o jsonpath='{.spec.taints}' | jq -r '.[] | select(.key | contains("StaticPods")) | .key + ":" + .effect' 2>/dev/null || echo "none")
echo "  Taint: $TAINT"

echo ""
echo "=== NPD Logs (last 15 lines) ==="
kubectl logs -n kube-system $NPD_POD --tail=15 2>/dev/null

echo ""
echo "=== Recent Node Events ==="
kubectl get events --field-selector involvedObject.kind=Node,involvedObject.name=$WORKER --sort-by='.lastTimestamp' | tail -8
