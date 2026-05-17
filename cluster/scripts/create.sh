#!/usr/bin/env bash
set -euo pipefail

CONFIG="$(dirname "$0")/../k3d-config.yaml"
k3d cluster create --config "$CONFIG"
kubectl cluster-info
