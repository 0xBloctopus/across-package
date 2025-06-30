def deploy_spokepool(plan, rpc_url, private_key):
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
    forge script script/DeploySpokePool.s.sol:DeployWETHAndMockSpokePool --broadcast --json --skip-simulation --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 
    """
    deployment = plan.run_sh(
        name="spokepool-deployer",
        description="Deploying WETH and SpokePool contracts",
        image="across-mock-contracts:0.0.1",
        env_vars=env_vars,
        run=cmd.strip()
    )
   
    plan.print(deployment)
    hubpool_address = deployment.output

    return {
        "hubpool_address": hubpool_address
    }
   