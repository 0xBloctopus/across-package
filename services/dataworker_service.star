def deploy_multi_chain_dataworker_service(plan, chains_config, hubpool_config, redis_url, dataworker_config={}):
    """
    Deploy a multi-chain dataworker service
    
    Args:
        plan: Kurtosis plan
        chains_config: List of chain configuration objects
        hubpool_config: HubPool configuration (rpc, private_key, address)
        redis_url: Redis connection URL
        dataworker_config: Optional dataworker configuration (polling_interval, block_range, etc.)
    
    Example chains_config:
    [
        {
            "chain_id": "8674520",
            "name": "ethereum",
            "rpc": "https://eth-rpc.com",
            "spokepool_address": "0x..."
        },
        {
            "chain_id": "1225280", 
            "name": "arbitrum",
            "rpc": "https://arb-rpc.com",
            "spokepool_address": "0x..."
        }
    ]
    
    Example hubpool_config:
    {
        "rpc": "https://hubpool-rpc.com",
        "private_key": "0x...",
        "address": "0x..."
    }
    """
    env_vars = {}
    
    # Add HubPool configuration
    env_vars["HUBPOOL_RPC"] = hubpool_config["rpc"]
    env_vars["HUBPOOL_PRIVATE_KEY"] = hubpool_config["private_key"]
    env_vars["HUBPOOL_ADDRESS"] = hubpool_config["address"]
    
    # Create a JSON string of chain configurations for the dataworker to parse
    chains_json = json.encode({
        chain["chain_id"]: {
            "type": chain["type"],
            "rpc": chain["rpc"],
            "spokePoolAddress": chain["spokepool_address"],
            "chainId": int(chain["chain_id"])
        }
        for chain in chains_config
    })
    
    env_vars["CHAINS_CONFIG"] = chains_json
    
    # Add Redis and dataworker configuration
    env_vars["REDIS_URL"] = redis_url
    env_vars["POLLING_INTERVAL"] = str(dataworker_config.get("polling_interval", 10000))
    env_vars["BLOCK_RANGE"] = str(dataworker_config.get("block_range", 100))
    env_vars["MIN_REFUND_VOLUME"] = str(dataworker_config.get("min_refund_volume", "0"))

    dataworker_service = plan.add_service(
        name="across-dataworker",
        config=ServiceConfig(
            image="raveenabhasin/across-mock-dataworker:0.0.4",  
            ports={},
            entrypoint=["node", "dist/index.js"],  
            cmd=[],
            env_vars=env_vars,
        ),
        description="Deploys the Across Protocol dataworker service for cross-chain operations."
    )
    return dataworker_service