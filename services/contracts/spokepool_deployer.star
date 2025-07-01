def deploy_spokepool(plan, rpc_url, private_key, weth_address):
    env_vars = {
        "RPC_URL": rpc_url,
        "PRIVATE_KEY": private_key,
        "WETH_ADDRESS": weth_address,
    }

    plan.run_sh(
        name="clean-forge-artifacts",
        description="Cleaning up outdated Forge artifacts",
        image="across-mock-contracts:0.0.2",
        run="forge clean"
    )

    cmd = """
    OUTPUT=$(forge script script/DeploySpokePool.s.sol:DeployWETHAndMockSpokePool --json --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1)
    echo "$OUTPUT" | jq -r 'select(.logs != null) | .logs[] | select(contains("MockSpokePool deployed at:")) | match("0x[a-fA-F0-9]{40}").string' 2>/dev/null | head -1 || echo "$OUTPUT" | grep -o "0x[a-fA-F0-9]\{40\}" | head -1
    """
    deployment = plan.run_sh(
        name="spokepool-deployer",
        description="Deploying WETH and SpokePool contracts",
        image="across-mock-contracts:0.0.2",
        env_vars=env_vars,
        run=cmd.strip()
    )
   
    plan.print(deployment)
    spokepool_address = deployment.output

    plan.print("SpokePool deployed at: " + spokepool_address)

    return {"spokepool_address": spokepool_address}

def initialize_spokepool(plan, rpc_url, private_key, spokepool_address, hubpool_address):
    env_vars = {
        "RPC_URL": rpc_url,
        "PRIVATE_KEY": private_key,
        "SPOKEPOOL_ADDRESS": spokepool_address,
        "HUBPOOL_ADDRESS": hubpool_address,
    }

    init_cmd = """
    cast send $SPOKEPOOL_ADDRESS "initialize(uint32,address,address)" 0 $HUBPOOL_ADDRESS $HUBPOOL_ADDRESS --rpc-url $RPC_URL --private-key $PRIVATE_KEY --gas-limit 500000
    """
    
    plan.run_sh(
        name="initialize-spokepool",
        description="Initializing SpokePool contract",
        image="across-mock-contracts:0.0.2",
        env_vars=env_vars,
        run=init_cmd.strip()
    )

    return {"status": "initialized"}
   