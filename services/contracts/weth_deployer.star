def deploy_weth(plan, rpc_url, private_key):
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
    forge script script/DeployWETH.s.sol:DeployWETH --broadcast --json --skip-simulation --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 \
    | grep -o '0x[a-fA-F0-9]\\{40\\}' | tail -n 1
    """
    deployment = plan.run_sh(
        name="weth-deployer",
        description="Deploying WETH contracts",
        image="across-mock-contracts:0.0.2",
        env_vars=env_vars,
        run=cmd.strip()
    )
   
    plan.print(deployment)
    weth_address = deployment.output

    return {
        "weth_address": weth_address
    }
   