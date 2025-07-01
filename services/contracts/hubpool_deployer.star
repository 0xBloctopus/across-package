def deploy_hub_pool_and_adapter(plan, rpc_url, private_key):
    env_vars = {
        "RPC_URL": rpc_url,
        "PRIVATE_KEY": private_key,
    }

    plan.run_sh(
        name="clean-forge-artifacts",
        description="Cleaning up outdated Forge artifacts",
        image="across-mock-contracts:0.0.2",
        run="forge clean"
    )

    cmd = """
    OUTPUT=$(forge script script/DeployHubPoolAndAdapter.s.sol:DeployHubPoolAndAdapter --json --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1)
    echo "$OUTPUT" | jq -r 'select(.logs != null) | .logs[] | select(contains("HubPool deployed at:")) | match("0x[a-fA-F0-9]{40}").string' 2>/dev/null | head -1 || echo "$OUTPUT" | grep -o "0x[a-fA-F0-9]\{40\}" | head -1
    """

    deployment = plan.run_sh(
        name="hub-pool-adapter-deployer",
        description="Deploying Adapter and HubPool contracts",
        image="across-mock-contracts:0.0.2",
        env_vars=env_vars,
        run=cmd.strip()
    )
   
    plan.print(deployment)
    hubpool_address = deployment.output

    return {
        "hubpool_address": hubpool_address
    }
   