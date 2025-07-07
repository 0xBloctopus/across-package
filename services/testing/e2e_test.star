def hex_to_dec(hex_str):
    return int(hex_str, 16)

def run_e2e_test(plan, networks, spokepool_a_address, spokepool_b_address, weth_a_address, weth_b_address):
    plan.print("Starting end-to-end cross-chain transfer test...")
    
    test_env = {
        "CHAIN_A_RPC": networks[0].rpc,
        "CHAIN_A_PRIVATE_KEY": networks[0].private_key,
        "CHAIN_B_RPC": networks[1].rpc,
        "SPOKEPOOL_A_ADDRESS": spokepool_a_address,
        "SPOKEPOOL_B_ADDRESS": spokepool_b_address,
        "WETH_A_ADDRESS": weth_a_address,
        "WETH_B_ADDRESS": weth_b_address,
    }

    # Get current time from the contract
    current_time_hex = $(cast call $SPOKEPOOL_A_ADDRESS 'getCurrentTime()' --rpc-url $CHAIN_A_RPC)
    current_time_dec=hex_to_dec(current_time_hex)

    # Get depositQuoteTimeBuffer from the contract
    quote_time_buffer_hex = $(
        cast call $SPOKEPOOL_A_ADDRESS 'depositQuoteTimeBuffer()' --rpc-url $CHAIN_A_RPC
    )
    quote_time_buffer_dec = hex_to_dec(quote_time_buffer_hex)
    
    deposit_cmd = """
    cast send $WETH_A_ADDRESS "approve(address,uint256)" $SPOKEPOOL_A_ADDRESS 1000000000000000000 --rpc-url $CHAIN_A_RPC --private-key $CHAIN_A_PRIVATE_KEY
    
    cast send $SPOKEPOOL_A_ADDRESS "depositV3(address,address,address,address,uint256,uint256,uint256,address,uint32,uint32,uint32,bytes)" \
        $(cast wallet address --private-key $CHAIN_A_PRIVATE_KEY) \
        $(cast wallet address --private-key $CHAIN_A_PRIVATE_KEY) \
        $WETH_A_ADDRESS \
        $WETH_B_ADDRESS \
        1000000000000000000 \
        950000000000000000 \
        $(cast chain-id --rpc-url $CHAIN_B_RPC) \
        0x0000000000000000000000000000000000000000 \
        current_time_dec \
        $(current_time_dec + quote_time_buffer_dec) \
        0 \
        0x \
        --rpc-url $CHAIN_A_RPC --private-key $CHAIN_A_PRIVATE_KEY
    """
    
    plan.run_sh(
        name="e2e-test-deposit",
        description="Making test deposit for end-to-end verification",
        image="across-mock-contracts:0.0.2",
        env_vars=test_env,
        run=deposit_cmd.strip()
    )
    
    plan.print("Test deposit completed. Relayer should automatically fulfill this deposit.")
    plan.print("DataWorker should then submit Merkle root to HubPool.")
    plan.print("Monitor service logs to verify complete flow execution.")
    
    return {"test_status": "initiated"}
