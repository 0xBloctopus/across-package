def deploy_multi_chain_relayer_service(plan, chains_config, redis_url, relayer_config={}):
    """
    Deploy a multi-chain relayer service
    
    Args:
        plan: Kurtosis plan
        chains_config: List of chain configuration objects
        redis_url: Redis connection URL
        relayer_config: Optional relayer configuration (polling_interval, block_range, etc.)
    
    Example chains_config:
    [
        {
            "chain_id": "1",
            "name": "ethereum",
            "rpc": "https://eth-mainnet.g.alchemy.com/v2/your-key",
            "private_key": "0x...",
            "spokepool_address": "0x..."
        },
        {
            "chain_id": "42161", 
            "name": "arbitrum",
            "rpc": "https://arb-mainnet.g.alchemy.com/v2/your-key",
            "private_key": "0x...",
            "spokepool_address": "0x..."
        }
    ]
    """
    env_vars = {}
    
    for chain in chains_config:
        chain_type = chain["type"].upper()
        env_vars["{}_RPC".format(chain_type)] = chain["rpc"]
        env_vars["{}_SPOKEPOOL_ADDRESS".format(chain_type)] = chain["spokepool_address"]
    
    env_vars["REDIS_URL"] = redis_url
    env_vars["RELAYER_PRIVATE_KEY"] = str(relayer_config.get("relayer_private_key"))
    env_vars["POLLING_INTERVAL"] = str(relayer_config.get("polling_interval", 5000))
    env_vars["BLOCK_RANGE"] = str(relayer_config.get("block_range", 100))
    env_vars["REPAYMENT_CHAIN_ID"] = str(relayer_config.get("repayment_chain_id", 1225280))
    env_vars["REPAYMENT_ADDRESS"] = relayer_config.get("repayment_address", "0x333F13a6913553EE8C380173B16449d1F7AD0aF9")
    
    chains_json = json.encode({
        chain["chain_id"]: {
            "rpc": "${{{}}}".format("{}_RPC".format(chain["type"].upper())),
            "spokePoolAddress": "${{{}}}".format("{}_SPOKEPOOL_ADDRESS".format(chain["type"].upper())),
            "chainId": int(chain["chain_id"]),
            "type": chain["type"]
        }
        for chain in chains_config
    })
    
    env_vars["CHAINS_CONFIG"] = chains_json
    
    relayer_service = plan.add_service(
        name="across-relayer",
        config=ServiceConfig(
            image="raveenabhasin/across-mock-relayer:0.0.7",  
            ports={},
            entrypoint=["node", "dist/index.js"],  
            cmd=[],
            env_vars=env_vars,
        ),
        description="Deploys the Across Protocol relayer service for cross-chain operations."
    )
    return relayer_service