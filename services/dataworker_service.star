def deploy_dataworker_service(plan, hubpool_config, chain_a_config, chain_b_config, redis_url):
    env_vars = {
        "HUBPOOL_RPC": hubpool_config.hubpool_rpc,
        "HUBPOOL_PRIVATE_KEY": hubpool_config.hubpool_private_key,
        "HUBPOOL_ADDRESS": hubpool_config.hubpool_address,
        "CHAIN_A_RPC": chain_a_config.rpc,
        "CHAIN_A_ID": str(chain_a_config.chain_id),
        "SPOKEPOOL_A_ADDRESS": chain_a_config.spokepool_address,
        "CHAIN_B_RPC": chain_b_config.rpc,
        "CHAIN_B_ID": str(chain_b_config.chain_id),
        "SPOKEPOOL_B_ADDRESS": chain_b_config.spokepool_address,
        "REDIS_URL": redis_url,
    }

    dataworker_service = plan.add_service(
        name="across-dataworker",
        config=ServiceConfig(
            image="raveenabhasin/across-mock-dataworker:0.0.1",  
            ports={},
            entrypoint=["node", "dist/index.js"],  
            cmd=[],
            env_vars=env_vars,
        ),
        description="Deploys the Across Protocol dataworker service for cross-chain operations."
    )

    return dataworker_service
