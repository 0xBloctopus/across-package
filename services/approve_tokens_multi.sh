#!/usr/bin/env bash
# approve_tokens_multi.sh
# Approve WETH(ETH) first, then USDC, per-network.
# Env:
#   RELAYER_PRIVATE_KEY          (required)
#   NETWORK_CONFIGS_APPROVAL     (required) CSV of "rpc|spokepool|weth|usdc"
#   ETH_APPROVAL_WEI             (optional) default: 1000 ETH in wei (1e21)
#   USDC_APPROVAL_TOKENS         (optional) default: 1000 (whole tokens, 6 decimals implied)

set -e

ETH_APPROVAL_WEI="${ETH_APPROVAL_WEI:-1000000000000000000000}"      
USDC_APPROVAL_TOKENS="${USDC_APPROVAL_TOKENS:-1000}"                

if [ -z "$RELAYER_PRIVATE_KEY" ]; then
  echo "Error: RELAYER_PRIVATE_KEY is required"; exit 1
fi
if [ -z "$NETWORK_CONFIGS_APPROVAL" ]; then
  echo "Error: NETWORK_CONFIGS_APPROVAL is required"
  echo "Format: rpc1|spokepool1|weth1|usdc1,rpc2|spokepool2|weth2|usdc2"; exit 1
fi

# Convert USDC whole tokens to 6-decimal base units
usdc_to_base() {
  local v="$1"
  if echo "$v" | grep -q '\.'; then
    awk -v val="$v" 'BEGIN{
      split(val,a,"."); whole=a[1]+0; frac=(length(a)>1)?a[2]:"";
      while(length(frac)<6){frac=frac "0"}; if(length(frac)>6){frac=substr(frac,1,6)}
      printf("%d%06d", whole, frac);
    }'
  else
    awk -v val="$v" 'BEGIN{printf "%.0f", val*1000000}'
  fi
}

USDC_APPROVAL_BASE="$(usdc_to_base "$USDC_APPROVAL_TOKENS")"
RELAYER_ADDR="$(cast wallet address --private-key "$RELAYER_PRIVATE_KEY")"

echo "=========================================="
echo "Generic Token Approval Script"
echo "=========================================="
echo "Relayer Address     : $RELAYER_ADDR"
echo "ETH Approval (wei)  : $ETH_APPROVAL_WEI"
echo "USDC Approval (base): $USDC_APPROVAL_BASE  (=$USDC_APPROVAL_TOKENS USDC)"
echo ""

approve_token() {
  local rpc_url="$1"
  local spender="$2"
  local token_addr="$3"
  local amount="$4"
  local label="$5"

  echo "  RPC     : $rpc_url"
  echo "  Spender : $spender"
  echo "  Token   : $token_addr"
  echo "  Label   : $label"
  echo "  Checking current allowance..."
  current_allowance=$(cast call "$token_addr" "allowance(address,address)(uint256)" \
    "$RELAYER_ADDR" "$spender" --rpc-url "$rpc_url")
  echo "  Current allowance: $current_allowance"

  echo "  Approving $amount..."
  tx_hash=$(cast send "$token_addr" "approve(address,uint256)" "$spender" "$amount" \
    --rpc-url "$rpc_url" --private-key "$RELAYER_PRIVATE_KEY" --json | jq -r '.transactionHash')

  if [ -n "$tx_hash" ] && [ "$tx_hash" != "null" ]; then
    echo "  ✅ $label approval tx: $tx_hash"
    new_allowance=$(cast call "$token_addr" "allowance(address,address)(uint256)" \
      "$RELAYER_ADDR" "$spender" --rpc-url "$rpc_url")
    echo "  New allowance: $new_allowance"
  else
    echo "  ❌ $label approval failed!"
    return 1
  fi
  echo ""
}

IFS=',' read -ra ENTRIES <<< "$NETWORK_CONFIGS_APPROVAL"
for entry in "${ENTRIES[@]}"; do
  IFS='|' read -ra P <<< "$entry"
  if [ ${#P[@]} -ne 4 ]; then
    echo "⚠️  Invalid network config: $entry"
    echo "    Expected: rpc|spokepool|weth|usdc"; echo ""; continue
  fi

  RPC="${P[0]}"; SPOKE="${P[1]}"; WETH="${P[2]}"; USDC="${P[3]}"

  echo "------------------------------------------"
  echo "Network: $RPC"
  # 1) WETH first (18 decimals)
  if [ -n "$WETH" ] && [ "$WETH" != "0x0000000000000000000000000000000000000000" ]; then
    approve_token "$RPC" "$SPOKE" "$WETH" "$ETH_APPROVAL_WEI" "WETH"
  else
    echo "  Skipping WETH: empty address"
  fi

  # 2) USDC next (6 decimals)
  if [ -n "$USDC" ] && [ "$USDC" != "0x0000000000000000000000000000000000000000" ]; then
    approve_token "$RPC" "$SPOKE" "$USDC" "$USDC_APPROVAL_BASE" "USDC"
  else
    echo "  Skipping USDC: empty address"
  fi
done

echo "=========================================="
echo "All approvals completed!"
echo "=========================================="