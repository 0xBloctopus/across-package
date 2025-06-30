def deploy_hub_pool_and_adapter(plan, rpc_url, private_key):
    env_vars = {
        "RPC_URL": rpc_url,
        "PRIVATE_KEY": private_key,
    }

    plan.run_sh(
        name="clean-forge-artifacts",
        description="Cleaning up outdated Forge artifacts",
        image="across-mock-contracts:0.0.1",
        run="forge clean"
    )

    cmd = """
    forge script script/DeployHubPoolAndAdapter.s.sol:DeployHubPoolAndAdapter --broadcast --json --skip-simulation --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 \
    | grep -o '0x[a-fA-F0-9]\\{40\\}' | tail -n 1
    """
    deployment = plan.run_sh(
        name="hub-pool-adapter-deployer",
        description="Deploying Adapter and HubPool contracts",
        image="across-mock-contracts:0.0.1",
        env_vars=env_vars,
        run=cmd.strip()
    )
   
    plan.print(deployment)
    hubpool_address = deployment.output

    return {
        "hubpool_address": hubpool_address
    }
   