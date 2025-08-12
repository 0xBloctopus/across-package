def run_eth_token_approval_script(plan, networks, relayer_private_key, amount="1000000000000000000000"):
    """
    Run the shell script to approve ETH tokens on SpokePool addresses using relayer private key
    
    Args:
        plan: Kurtosis plan object
        networks: List of network configurations with chain_id, rpc, spokepool_address, and weth_address
        relayer_private_key: Private key for the relayer
        amount: Amount to approve in wei (default: 1000 ETH)
    """
    
    # Build network configurations string for environment variable
    network_configs = []
    for network in networks:
        weth_address = ""
        for token in network.get("tokens", []):
            if token["symbol"] == "ETH":
                weth_address = token["address"]
                break
        
        if weth_address:
            config_string = "{}|{}|{}".format(
                network["rpc"],
                network["spokepool_address"],
                weth_address
            )
            network_configs.append(config_string)
    
    network_configs_env = ",".join(network_configs)
    
    # Upload the shell script to the service
    script_artifact = plan.upload_files(
        name="eth-approval-script",
        src="approve_eth_tokens.sh",
        description="ETH token approval shell script"
    )
    
    # Set environment variables
    env_vars = {
        "RELAYER_PRIVATE_KEY": relayer_private_key,
        "NETWORK_CONFIGS": network_configs_env
    }
    
    # Run the approval script
    result = plan.run_sh(
        name="run-eth-token-approvals",
        description="Execute ETH token approvals on all SpokePool addresses",
        image="raveenabhasin/across-mock-contracts:0.0.9",
        files={
            "/scripts": script_artifact
        },
        env_vars=env_vars,
        run="chmod +x /scripts/* && /scripts/approve_eth_tokens.sh " + amount
    )
    
    plan.print("ETH Token Approval Script Output:")
    plan.print(result.output)
    
    return result
