#!/bin/bash

# Script to approve ETH tokens on SpokePool addresses using relayer private key
# Usage: ./approve_eth_tokens.sh [amount]

set -e

DEFAULT_AMOUNT="1000000000000000000000"
AMOUNT="${1:-$DEFAULT_AMOUNT}"

if [ -z "$RELAYER_PRIVATE_KEY" ]; then
    echo "Error: RELAYER_PRIVATE_KEY environment variable is required"
    exit 1
fi

if [ -z "$NETWORK_CONFIGS" ]; then
    echo "Error: NETWORK_CONFIGS environment variable is required"
    echo "Format: rpc1|spokepool1|weth1,rpc2|spokepool2|weth2"
    exit 1
fi

echo "=========================================="
echo "ETH Token Approval Script"
echo "=========================================="
echo "Approval Amount: $AMOUNT wei"
echo "Relayer Address: $(cast wallet address --private-key $RELAYER_PRIVATE_KEY)"
echo ""

approve_token() {
    local rpc_url="$1"
    local spokepool_address="$2"
    local token_address="$3"
    
    echo "  RPC: $rpc_url"
    echo "  SpokePool: $spokepool_address"
    echo "  Token: $token_address"
    
    # Check current allowance
    echo "  Checking current allowance..."
    current_allowance=$(cast call $token_address "allowance(address,address)(uint256)" \
        $(cast wallet address --private-key $RELAYER_PRIVATE_KEY) \
        $spokepool_address \
        --rpc-url $rpc_url)
    
    echo "  Current allowance: $current_allowance"
    
    # Approve tokens
    echo "  Approving $AMOUNT tokens..."
    tx_hash=$(cast send $token_address "approve(address,uint256)" \
        $spokepool_address \
        $AMOUNT \
        --rpc-url $rpc_url \
        --private-key $RELAYER_PRIVATE_KEY \
        --json | jq -r '.transactionHash')
    
    if [ "$tx_hash" != "null" ] && [ -n "$tx_hash" ]; then
        echo "  ✅ Approval successful! TX: $tx_hash"
        
        # Verify new allowance
        echo "  Verifying new allowance..."
        new_allowance=$(cast call $token_address "allowance(address,address)(uint256)" \
            $(cast wallet address --private-key $RELAYER_PRIVATE_KEY) \
            $spokepool_address \
            --rpc-url $rpc_url)
        
        echo "  New allowance: $new_allowance"
    else
        echo "  ❌ Approval failed!"
        return 1
    fi
    
    echo ""
}

# Process all networks from environment configuration
IFS=',' read -ra NETWORK_LIST <<< "$NETWORK_CONFIGS"
for network_config in "${NETWORK_LIST[@]}"; do
    IFS='|' read -ra CONFIG_PARTS <<< "$network_config"
    
    if [ ${#CONFIG_PARTS[@]} -eq 3 ]; then
        rpc_url="${CONFIG_PARTS[0]}"
        spokepool_address="${CONFIG_PARTS[1]}"
        weth_address="${CONFIG_PARTS[2]}"
        
        approve_token "$rpc_url" "$spokepool_address" "$weth_address"
    else
        echo "⚠️  Invalid network configuration: $network_config"
        echo "  Expected format: rpc|spokepool|weth"
        echo ""
    fi
done

echo "=========================================="
echo "All approvals completed!"
echo "=========================================="