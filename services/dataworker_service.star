def deploy_dataworker_service(plan, hubpool_config, chain_a_config, chain_b_config, hubpool_address, spokepool_a_address, spokepool_b_address, redis_url):
    env_vars = {
        "HUBPOOL_RPC": hubpool_config.rpc,
        "HUBPOOL_PRIVATE_KEY": hubpool_config.private_key,
        "HUBPOOL_ADDRESS": hubpool_address,
        "CHAIN_A_RPC": chain_a_config.rpc,
        "CHAIN_A_ID": str(chain_a_config.chain_id),
        "SPOKEPOOL_A_ADDRESS": spokepool_a_address,
        "CHAIN_B_RPC": chain_b_config.rpc,
        "CHAIN_B_ID": str(chain_b_config.chain_id),
        "SPOKEPOOL_B_ADDRESS": spokepool_b_address,
        "REDIS_URL": redis_url,
    }

    plan.upload_files(
        src="dataworker",
        name="dataworker-code"
    )

    dataworker_service = plan.add_service(
        name="across-dataworker",
        config=ServiceConfig(
            image="node:18-alpine",
            ports={"api": PortSpec(number=3001, transport_protocol="TCP")},
            env_vars=env_vars,
            cmd=["/bin/sh", "-c", "cd /app && npm install && npm run build && npm start"],
            files={"/app": "dataworker-code"}
        )
    )

    return dataworker_service
