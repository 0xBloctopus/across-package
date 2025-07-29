#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage: $0 <direction>"
  echo "  direction: a2b or b2a"
  exit 1
fi

DIRECTION="$1"

CHAIN_A_RPC="https://eth-sepolia.public.blastapi.io"
CHAIN_B_RPC="https://sepolia-rollup.arbitrum.io/rpc"
CHAIN_A_PRIVATE_KEY="0x35c...."
CHAIN_B_PRIVATE_KEY="0x35c...."  
SPOKEPOOL_A_ADDRESS="0x2e464Fc721F65921E6816c852F59ecb9147DdC9C"
SPOKEPOOL_B_ADDRESS="0xE06BD938cAe98e180A31a1eb8b229D000A02EBd1"
WETH_A_ADDRESS="0x6b73250CFF2DCE3426D41a45f6f7543C65786d96"
WETH_B_ADDRESS="0xbDA57395A0A7953D882434DD1F40f5d410a8d973"

if [ "$DIRECTION" = "a2b" ]; then
  SRC_CHAIN_RPC="$CHAIN_A_RPC"
  DST_CHAIN_RPC="$CHAIN_B_RPC"
  SRC_PRIVATE_KEY="$CHAIN_A_PRIVATE_KEY"
  SRC_SPOKEPOOL="$SPOKEPOOL_A_ADDRESS"
  DST_SPOKEPOOL="$SPOKEPOOL_B_ADDRESS"
  SRC_WETH="$WETH_A_ADDRESS"
  DST_WETH="$WETH_B_ADDRESS"
elif [ "$DIRECTION" = "b2a" ]; then
  SRC_CHAIN_RPC="$CHAIN_B_RPC"
  DST_CHAIN_RPC="$CHAIN_A_RPC"
  SRC_PRIVATE_KEY="$CHAIN_B_PRIVATE_KEY"
  SRC_SPOKEPOOL="$SPOKEPOOL_B_ADDRESS"
  DST_SPOKEPOOL="$SPOKEPOOL_A_ADDRESS"
  SRC_WETH="$WETH_B_ADDRESS"
  DST_WETH="$WETH_A_ADDRESS"
else
  echo "Invalid direction: $DIRECTION. Use 'a2b' or 'b2a'."
  exit 1
fi

EXCLUSIVE_RELAYER="0xca0AAC84A57e239A2918E9537BCc3Ee29E24b6cd"  # Set your exclusive relayer address here
EXCLUSIVITY_DEADLINE_DELTA=300  # Set to 300 or 400 as needed

hex_to_dec() {
  printf "%d" "$((16#${1#0x}))"
}

current_time_hex=$(cast call $SRC_SPOKEPOOL "getCurrentTime()" --rpc-url $SRC_CHAIN_RPC)
current_time_dec=$(hex_to_dec $current_time_hex)

quote_time_buffer_hex=$(cast call $SRC_SPOKEPOOL "depositQuoteTimeBuffer()" --rpc-url $SRC_CHAIN_RPC)
quote_time_buffer_dec=$(hex_to_dec $quote_time_buffer_hex)

fill_deadline=$((current_time_dec + quote_time_buffer_dec))

exclusivity_deadline=$((current_time_dec + EXCLUSIVITY_DEADLINE_DELTA))

chain_id=$(cast chain-id --rpc-url $DST_CHAIN_RPC)

sender_address=$(cast wallet address --private-key $SRC_PRIVATE_KEY)
recipient_address=0xe50b254a5571B59B521e75622C2573067F893132

cast send $SRC_WETH "approve(address,uint256)" $SRC_SPOKEPOOL 10000000 --rpc-url $SRC_CHAIN_RPC --private-key $SRC_PRIVATE_KEY

cast send $SRC_SPOKEPOOL "depositV3(address,address,address,address,uint256,uint256,uint256,address,uint32,uint32,uint32,bytes)" \
  $sender_address \
  $recipient_address \
  $SRC_WETH \
  $DST_WETH \
  20000 \
  5000 \
  $chain_id \
  0x0000000000000000000000000000000000000000 \
  $current_time_dec \
  $fill_deadline \
  0 \
  0x \
  --rpc-url $SRC_CHAIN_RPC --private-key $SRC_PRIVATE_KEY

echo "DepositV3 transaction sent. Monitor relayer and DataWorker logs for full flow." 