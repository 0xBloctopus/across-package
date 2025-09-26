def register_spoke_pools(plan, rpc, private_key, hubpool_address, chain_id, adapter_address, spokepool_address):
    env_vars = {
        "RPC_URL": rpc,
        "PRIVATE_KEY": private_key,
        "HUBPOOL_ADDRESS": hubpool_address,
        "ADAPTER_ADDRESS": adapter_address,
        "SPOKEPOOL_ADDRESS": spokepool_address,
        "CHAIN_ID": chain_id
    }

    register_a_cmd = """
    cast send $HUBPOOL_ADDRESS "setCrossChainContracts(uint256,address,address)" $CHAIN_ID $ADAPTER_ADDRESS $SPOKEPOOL_ADDRESS --rpc-url $RPC_URL --private-key $PRIVATE_KEY
    """

    plan.run_sh(
        name="register-spokepool",
        description="Set Cross Chain Contracts on HubPool",
        image="raveenabhasin/across-mock-contracts:0.0.9",
        env_vars=env_vars,
        run=register_a_cmd.strip()
    )

    # Verification step: call crossChainContracts to check registration
    verify_cmd = """
    cast call $HUBPOOL_ADDRESS "crossChainContracts(uint256)(address,address)" $CHAIN_ID --rpc-url $RPC_URL --json
    """
    verification = plan.run_sh(
        name="verify-registration",
        description="Verify Cross Chain Contracts registration",
        image="raveenabhasin/across-mock-contracts:0.0.9",
        env_vars=env_vars,
        run=verify_cmd.strip()
    )

    plan.print("Verification output:")
    plan.print(verification.output)

    return {"status": "registered", "verification": verification.output}
