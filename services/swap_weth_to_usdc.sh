# #!/usr/bin/env bash
# set -euo pipefail

# # swap_weth_to_usdc.sh
# # Wrap ETH -> WETH, approve router, and swap WETH->USDC via Uniswap V2 using cast.

# usage() {
#   cat <<'USAGE'
# Usage:
#   ./swap_weth_to_usdc.sh \
#     --rpc https://... \
#     --pk 0xYOUR_PRIVATE_KEY \
#     --weth 0xWETH \
#     --usdc 0xUSDC \
#     --router 0xUniswapV2Router \
#     --amount-eth 0.01 \
#     [--min-usdc 0] \
#     [--to 0xRecipient] \
#     [--deadline-secs 600]

# Notes:
# - --min-usdc is in *USDC whole tokens* (decimals=6). If omitted, 0 is used (DANGEROUS: no slippage protection).
# - You can also set environment variables instead of flags:
#     RPC_URL, PRIVATE_KEY, WETH, USDC, ROUTER, AMOUNT_ETH, MIN_USDC, TO, DEADLINE_SECS
# - Requires Foundry (cast) installed.
# USAGE
# }

# # Default/empty values
# RPC_URL="${RPC_URL:-}"
# PRIVATE_KEY="${PRIVATE_KEY:-}"
# WETH="${WETH:-}"
# USDC="${USDC:-}"
# ROUTER="${ROUTER:-}"
# AMOUNT_ETH="${AMOUNT_ETH:-}"
# MIN_USDC="${MIN_USDC:-0}"
# TO="${TO:-}"
# DEADLINE_SECS="${DEADLINE_SECS:-600}"

# # Parse args
# while [[ $# -gt 0 ]]; do
#   case "$1" in
#     --rpc) RPC_URL="$2"; shift 2;;
#     --pk) PRIVATE_KEY="$2"; shift 2;;
#     --weth) WETH="$2"; shift 2;;
#     --usdc) USDC="$2"; shift 2;;
#     --router) ROUTER="$2"; shift 2;;
#     --amount-eth) AMOUNT_ETH="$2"; shift 2;;
#     --min-usdc) MIN_USDC="$2"; shift 2;;
#     --to) TO="$2"; shift 2;;
#     --deadline-secs) DEADLINE_SECS="$2"; shift 2;;
#     -h|--help) usage; exit 0;;
#     *) echo "Unknown arg: $1"; usage; exit 1;;
#   esac
# done

# # Basic validation
# [[ -z "${RPC_URL}" ]] && { echo "Missing --rpc (or RPC_URL)"; exit 1; }
# [[ -z "${WETH}" ]] && { echo "Missing --weth (or WETH)"; exit 1; }
# [[ -z "${USDC}" ]] && { echo "Missing --usdc (or USDC)"; exit 1; }
# [[ -z "${ROUTER}" ]] && { echo "Missing --router (or ROUTER)"; exit 1; }
# [[ -z "${AMOUNT_ETH}" ]] && { echo "Missing --amount-eth (or AMOUNT_ETH)"; exit 1; }

# # Resolve signer address if not provided explicitly
# if [[ -z "${TO}" ]]; then
#   if [[ -n "${PRIVATE_KEY}" ]]; then
#     # Derive address from PK
#     TO=$(cast wallet address --private-key "${PRIVATE_KEY}")
#   else
#     echo "No --to and no --pk provided. Either supply --to or --pk so we can derive the sender/recipient address."
#     exit 1
#   fi
# fi

# # Convert amounts
# AMOUNT_IN_WEI=$(cast --to-wei "${AMOUNT_ETH}" ether)

# # MIN_USDC is provided in *whole tokens* with 6 decimals; convert to base units.
# # If MIN_USDC contains a decimal point, convert using awk; else assume it's already a plain number (e.g., 12.345678)
# if [[ "${MIN_USDC}" == *.* ]]; then
#   # Normalize to 6 decimals
#   MIN_USDC_BASE=$(awk -v v="${MIN_USDC}" 'BEGIN{
#     split(v,a,".");
#     whole = a[1]+0;
#     frac = (length(a)>1)?a[2]:"";
#     while(length(frac)<6){frac=frac "0"}
#     if(length(frac)>6){frac=substr(frac,1,6)}
#     # Construct integer
#     printf("%d%06d", whole, frac);
#   }')
# else
#   # Treat as whole-number tokens, scale by 1e6
#   MIN_USDC_BASE=$(awk -v v="${MIN_USDC}" 'BEGIN{printf "%.0f", v*1000000}')
# fi

# # Compute deadline (unix seconds)
# NOW=$(date +%s)
# DEADLINE=$(( NOW + DEADLINE_SECS ))

# echo "=== Config ==="
# echo "RPC_URL        : ${RPC_URL}"
# echo "Signer/To      : ${TO}"
# echo "WETH           : ${WETH}"
# echo "USDC           : ${USDC}"
# echo "Router         : ${ROUTER}"
# echo "Amount ETH     : ${AMOUNT_ETH} (wei: ${AMOUNT_IN_WEI})"
# echo "Min USDC       : ${MIN_USDC} (base: ${MIN_USDC_BASE})"
# echo "Deadline (sec) : ${DEADLINE} (in ${DEADLINE_SECS}s)"
# echo

# # --- Step 0: (Optional) Check pair + reserves for sanity ---
# echo "Checking factory/pair/reserves (optional sanity checks)..."
# FACTORY=$(cast call "${ROUTER}" "factory()(address)" --rpc-url "${RPC_URL}")
# PAIR=$(cast call "${FACTORY}" "getPair(address,address)(address)" "${WETH}" "${USDC}" --rpc-url "${RPC_URL}")
# echo "Factory: ${FACTORY}"
# echo "Pair   : ${PAIR}"

# # Normalize case for Bash 3.x compatibility (no ${VAR,,})
# PAIR_NORM=$(printf "%s" "${PAIR}" | tr '[:upper:]' '[:lower:]')
# if [ "${PAIR_NORM}" = "0x0000000000000000000000000000000000000000" ]; then
#   echo "ERROR: WETH/USDC pair does not exist."
#   exit 1
# fi

# RESERVES=$(cast call "${PAIR}" "getReserves()(uint112,uint112,uint32)" --rpc-url "${RPC_URL}")
# echo "Reserves: ${RESERVES}"

# # --- Step 1: Wrap ETH -> WETH ---
# echo
# echo "Wrapping ${AMOUNT_ETH} ETH to WETH..."
# if [[ -n "${PRIVATE_KEY}" ]]; then
#   cast send "${WETH}" "deposit()" \
#     --value "${AMOUNT_IN_WEI}" \
#     --private-key "${PRIVATE_KEY}" \
#     --rpc-url "${RPC_URL}"
# else
#   echo "No --pk provided. Please export PRIVATE_KEY or pass --pk to send transactions."
#   exit 1
# fi

# # --- Step 2: Approve WETH -> Router ---
# echo
# echo "Approving router to spend WETH (amount: ${AMOUNT_IN_WEI})..."
# cast send "${WETH}" "approve(address,uint256)" "${ROUTER}" "${AMOUNT_IN_WEI}" \
#   --private-key "${PRIVATE_KEY}" \
#   --rpc-url "${RPC_URL}"

# # --- Step 3: (Optional) Quote expected USDC out ---
# # You can uncomment the block below if you want to see an on-chain quote.
# # NOTE: This does NOT set slippage automatically; it's informational unless you wire it in.
# # echo
# # echo "Fetching getAmountsOut quote (WETH -> USDC)..."
# # QUOTE=$(cast call "${ROUTER}" "getAmountsOut(uint256,address[])(uint256[])" "${AMOUNT_IN_WEI}" "[${WETH},${USDC}]" --rpc-url "${RPC_URL}")
# # echo "AmountsOut (wei/base units): ${QUOTE}"
# # # Output typically looks like: "[<inWei>,<outBaseUnits>]"
# # # You can parse and compute 95% min-out with jq/awk if desired.

# # --- Step 4: Swap WETH -> USDC ---
# echo
# echo "Swapping via Uniswap V2: swapExactTokensForTokens..."
# echo "Path: [${WETH}, ${USDC}]"
# cast send "${ROUTER}" \
#   "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)" \
#   "${AMOUNT_IN_WEI}" \
#   "${MIN_USDC_BASE}" \
#   "[${WETH},${USDC}]" \
#   "${TO}" \
#   "${DEADLINE}" \
#   --private-key "${PRIVATE_KEY}" \
#   --rpc-url "${RPC_URL}"

# echo
# echo "Done ✅"

#!/bin/bash
# swap_eth_to_usdc_multi.sh
# Multi-chain ETH->USDC swap using Foundry's `cast`, following the same pattern as approve_eth_tokens.sh
# Usage: ./swap_eth_to_usdc_multi.sh [amount_eth] [min_usdc] [deadline_secs]
#   amount_eth    : ETH amount to wrap & swap (default: 2)
#   min_usdc      : Minimum USDC out (whole tokens, 6 decimals implied; default: 0)
#   deadline_secs : Seconds from now for tx deadline (default: 600)

set -e

AMOUNT_ETH="${1:-2}"
MIN_USDC_WHOLE="${2:-0}"
DEADLINE_SECS="${3:-600}"

if [ -z "$RELAYER_PRIVATE_KEY" ]; then
  echo "Error: RELAYER_PRIVATE_KEY environment variable is required"
  exit 1
fi

if [ -z "$NETWORK_CONFIGS_SWAP" ]; then
  echo "Error: NETWORK_CONFIGS_SWAP environment variable is required"
  echo "Format: rpc1|weth1|usdc1|router1,rpc2|weth2|usdc2|router2"
  exit 1
fi

# Optional: override recipient; defaults to the RELAYER address
TO_ADDRESS="${TO:-$(cast wallet address --private-key "$RELAYER_PRIVATE_KEY")}"

# Convert helpers (Bash 3.x compatible)
to_wei() {
  # $1: ETH amount as string (may be decimal)
  cast --to-wei "$1" ether
}

usdc_to_base() {
  # Convert whole-token USDC (possibly with decimals in string) to base units (6 decimals)
  # $1: MIN_USDC_WHOLE as string (e.g., "3800" or "12.345678")
  local v="$1"
  if echo "$v" | grep -q '\.'; then
    # Normalize to exactly 6 decimals using awk
    awk -v val="$v" 'BEGIN{
      split(val,a,".");
      whole = a[1]+0;
      frac  = (length(a)>1)?a[2]:"";
      while(length(frac)<6){frac=frac "0"}
      if(length(frac)>6){frac=substr(frac,1,6)}
      printf("%d%06d", whole, frac);
    }'
  else
    # No decimal point: multiply by 1e6
    awk -v val="$v" 'BEGIN{printf "%.0f", val*1000000}'
  fi
}

AMOUNT_IN_WEI="$(to_wei "$AMOUNT_ETH")"
MIN_USDC_BASE="$(usdc_to_base "$MIN_USDC_WHOLE")"
NOW="$(date +%s)"
DEADLINE="$(( NOW + DEADLINE_SECS ))"

echo "=========================================="
echo "ETH -> USDC Swap Script"
echo "=========================================="
echo "Relayer Address : $TO_ADDRESS"
echo "Amount (ETH)    : $AMOUNT_ETH (wei: $AMOUNT_IN_WEI)"
echo "Min USDC (whole): $MIN_USDC_WHOLE (base: $MIN_USDC_BASE)"
echo "Deadline (secs) : $DEADLINE (in $DEADLINE_SECS s)"
echo ""

wrap_eth() {
  local rpc_url="$1"
  local weth_addr="$2"
  local amount_wei="$3"

  echo "  Wrapping ETH -> WETH..."
  tx_hash=$(cast send "$weth_addr" "deposit()" \
    --value "$amount_wei" \
    --rpc-url "$rpc_url" \
    --private-key "$RELAYER_PRIVATE_KEY" \
    --json | jq -r '.transactionHash')

  if [ -n "$tx_hash" ] && [ "$tx_hash" != "null" ]; then
    echo "  ✅ Wrapped: $tx_hash"
  else
    echo "  ❌ Wrap failed!"
    return 1
  fi
}

approve_weth() {
  local rpc_url="$1"
  local weth_addr="$2"
  local router_addr="$3"
  local amount_wei="$4"

  echo "  Approving router to spend WETH..."
  tx_hash=$(cast send "$weth_addr" "approve(address,uint256)" \
    "$router_addr" "$amount_wei" \
    --rpc-url "$rpc_url" \
    --private-key "$RELAYER_PRIVATE_KEY" \
    --json | jq -r '.transactionHash')

  if [ -n "$tx_hash" ] && [ "$tx_hash" != "null" ]; then
    echo "  ✅ Approved: $tx_hash"
  else
    echo "  ❌ Approve failed!"
    return 1
  fi
}

swap_weth_to_usdc() {
  local rpc_url="$1"
  local weth_addr="$2"
  local usdc_addr="$3"
  local router_addr="$4"
  local amount_wei="$5"
  local min_out_base="$6"
  local recipient="$7"
  local deadline_ts="$8"

  echo "  Swapping WETH -> USDC..."
  # Note: address[] encoding in cast uses [a,b]
  tx_hash=$(cast send "$router_addr" \
    "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)" \
    "$amount_wei" \
    "$min_out_base" \
    "[$weth_addr,$usdc_addr]" \
    "$recipient" \
    "$deadline_ts" \
    --rpc-url "$rpc_url" \
    --private-key "$RELAYER_PRIVATE_KEY" \
    --json | jq -r '.transactionHash')

  if [ -n "$tx_hash" ] && [ "$tx_hash" != "null" ]; then
    echo "  ✅ Swap tx: $tx_hash"
  else
    echo "  ❌ Swap failed!"
    return 1
  fi
}

# Loop networks like approve_eth_tokens.sh
IFS=',' read -ra NETWORK_LIST <<< "$NETWORK_CONFIGS_SWAP"
for entry in "${NETWORK_LIST[@]}"; do
  IFS='|' read -ra PARTS <<< "$entry"

  if [ ${#PARTS[@]} -eq 4 ]; then
    rpc_url="${PARTS[0]}"
    weth_addr="${PARTS[1]}"
    usdc_addr="${PARTS[2]}"
    router_addr="${PARTS[3]}"

    echo "------------------------------------------"
    echo "RPC    : $rpc_url"
    echo "WETH   : $weth_addr"
    echo "USDC   : $usdc_addr"
    echo "ROUTER : $router_addr"

    # Step 1: Wrap ETH -> WETH
    wrap_eth "$rpc_url" "$weth_addr" "$AMOUNT_IN_WEI"

    # Step 2: Approve router
    approve_weth "$rpc_url" "$weth_addr" "$router_addr" "$AMOUNT_IN_WEI"

    # Step 3: Swap
    swap_weth_to_usdc "$rpc_url" "$weth_addr" "$usdc_addr" "$router_addr" "$AMOUNT_IN_WEI" "$MIN_USDC_BASE" "$TO_ADDRESS" "$DEADLINE"

    echo ""
  else
    echo "⚠️  Invalid network configuration: $entry"
    echo "   Expected format: rpc|weth|usdc|router"
    echo ""
  fi
done

echo "=========================================="
echo "All swaps completed!"
echo "=========================================="