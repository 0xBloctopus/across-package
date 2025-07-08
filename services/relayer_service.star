def deploy_relayer_service(plan, chain_a_config, chain_b_config, spokepool_a_address, spokepool_b_address, redis_url):
    env_vars = {
        "CHAIN_A_RPC": chain_a_config.rpc,
        "CHAIN_A_PRIVATE_KEY": chain_a_config.private_key,
        "CHAIN_A_ID": str(chain_a_config.chain_id),
        "SPOKEPOOL_A_ADDRESS": spokepool_a_address,
        "CHAIN_B_RPC": chain_b_config.rpc,
        "CHAIN_B_PRIVATE_KEY": chain_b_config.private_key,
        "CHAIN_B_ID": str(chain_b_config.chain_id),
        "SPOKEPOOL_B_ADDRESS": spokepool_b_address,
        "REDIS_URL": redis_url,
    }

    plan.upload_files(
        src="./relayer",
        name="relayer-code"
    )

    relayer_service = plan.add_service(
        name="across-relayer",
        config=ServiceConfig(
            image="node:18-alpine",
            ports={"api": PortSpec(number=3000, transport_protocol="TCP")},
            env_vars=env_vars,
            cmd=["/bin/sh", "-c", "cd /app && npm install && npm run build && npm start"],
            files={"/app": "relayer-code"}
        )
    )

    return relayer_service
