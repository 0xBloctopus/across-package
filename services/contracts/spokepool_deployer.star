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
    forge script script/DeploySpokePool.s.sol:DeployWETHAndMockSpokePool --broadcast --json --skip-simulation --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 \
    | grep -o '0x[a-fA-F0-9]\\{40\\}' | tail -n 1
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

    return {
        "spokepool_address": spokepool_address
    }
   