#!/bin/bash

# --- User configuration ---
CHAIN_A_RPC="https://eth-sepolia.public.blastapi.io"
CHAIN_B_RPC="https://sepolia-rollup.arbitrum.io/rpc"
CHAIN_A_PRIVATE_KEY="0x35c5c71f673bf923f46fb572212ea7160b876290689ab2ce298925ad0eb1b167"
SPOKEPOOL_A_ADDRESS="0x2e464Fc721F65921E6816c852F59ecb9147DdC9C"
WETH_A_ADDRESS="0x6b73250CFF2DCE3426D41a45f6f7543C65786d96"
WETH_B_ADDRESS="0xB28C2c9d31Aa1C7b08C59C0e515BC26323aF36Cd"

# --- Helper: hex to dec ---
hex_to_dec() {
  printf "%d" "$((16#${1#0x}))"
}

# --- Get current time from contract ---
current_time_hex=$(cast call $SPOKEPOOL_A_ADDRESS "getCurrentTime()" --rpc-url $CHAIN_A_RPC)
current_time_dec=$(hex_to_dec $current_time_hex)

# --- Get depositQuoteTimeBuffer from contract ---
quote_time_buffer_hex=$(cast call $SPOKEPOOL_A_ADDRESS "depositQuoteTimeBuffer()" --rpc-url $CHAIN_A_RPC)
quote_time_buffer_dec=$(hex_to_dec $quote_time_buffer_hex)

# --- Calculate fillDeadline ---
fill_deadline=$((current_time_dec + quote_time_buffer_dec))

# --- Get chain ID for destination chain ---
chain_id=$(cast chain-id --rpc-url $CHAIN_B_RPC)

# --- Get sender address from private key ---
sender_address=$(cast wallet address --private-key $CHAIN_A_PRIVATE_KEY)

# --- Approve SpokePool to spend WETH ---
cast send $WETH_A_ADDRESS "approve(address,uint256)" $SPOKEPOOL_A_ADDRESS 10000000 --rpc-url $CHAIN_A_RPC --private-key $CHAIN_A_PRIVATE_KEY

# --- Call depositV3 ---
cast send $SPOKEPOOL_A_ADDRESS "depositV3(address,address,address,address,uint256,uint256,uint256,address,uint32,uint32,uint32,bytes)" \
  $sender_address \
  $sender_address \
  $WETH_A_ADDRESS \
  $WETH_B_ADDRESS \
  2000000 \
  50000 \
  $chain_id \
  0x0000000000000000000000000000000000000000 \
  $current_time_dec \
  $fill_deadline \
  0 \
  0x \
  --rpc-url $CHAIN_A_RPC --private-key $CHAIN_A_PRIVATE_KEY

echo "DepositV3 transaction sent. Monitor relayer and DataWorker logs for full flow." 