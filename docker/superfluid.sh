#!/usr/bin/env bash

set -euo pipefail

: "${RPC_URL:?RPC_URL env var must be set (e.g. http://anvil:8545)}"

echo "Waiting for Anvil at "$RPC_URL"..."
until cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; do
  echo "  still waiting..."
  sleep 1
done

echo "Anvil is up, deploying Superfluid framework..."

CREATE_NEW_RESOLVER=1 npx truffle exec --network testing ops-scripts/deploy-framework.js