def register_spoke_pools(plan, hubpool_rpc, hubpool_private_key, hubpool_address, chain_a_id, spokepool_a_address, chain_b_id, spokepool_b_address):
    env_vars = {
        "RPC_URL": hubpool_rpc,
        "PRIVATE_KEY": hubpool_private_key,
        "HUBPOOL_ADDRESS": hubpool_address,
    }

    register_a_cmd = """
    cast send $HUBPOOL_ADDRESS "setCrossChainContracts(uint256,address,address)" {chain_a_id} 0x0000000000000000000000000000000000000000 $SPOKEPOOL_A_ADDRESS --rpc-url $RPC_URL --private-key $PRIVATE_KEY
    """.format(chain_a_id=chain_a_id)

    plan.run_sh(
        name="register-spokepool-a",
        description="Registering SpokePool A with HubPool",
        image="across-mock-contracts:0.0.2",
        env_vars=env_vars | {"SPOKEPOOL_A_ADDRESS": spokepool_a_address},
        run=register_a_cmd.strip()
    )

    register_b_cmd = """
    cast send $HUBPOOL_ADDRESS "setCrossChainContracts(uint256,address,address)" {chain_b_id} 0x0000000000000000000000000000000000000000 $SPOKEPOOL_B_ADDRESS --rpc-url $RPC_URL --private-key $PRIVATE_KEY
    """.format(chain_b_id=chain_b_id)

    plan.run_sh(
        name="register-spokepool-b", 
        description="Registering SpokePool B with HubPool",
        image="across-mock-contracts:0.0.2",
        env_vars=env_vars | {"SPOKEPOOL_B_ADDRESS": spokepool_b_address},
        run=register_b_cmd.strip()
    )

    return {"status": "registered"}
