def deploy_relayer_service(plan, chain_a_config, chain_b_config, repayment_address, polling_interval, block_range, relayer_private_key, redis_url):
    env_vars = {
        "CHAIN_A_RPC": chain_a_config.rpc,
        "CHAIN_A_PRIVATE_KEY": chain_a_config.private_key,
        "CHAIN_A_ID": str(chain_a_config.chain_id),
        "SPOKEPOOL_A_ADDRESS": chain_a_config.spokepool_address,
        "CHAIN_B_RPC": chain_b_config.rpc,
        "CHAIN_B_PRIVATE_KEY": chain_b_config.private_key,
        "CHAIN_B_ID": str(chain_b_config.chain_id),
        "SPOKEPOOL_B_ADDRESS": chain_b_config.spokepool_address,
        "REDIS_URL": redis_url,
        "POLLING_INTERVAL": str(polling_interval), 
        "BLOCK_RANGE": str(block_range),
        "REPAYMENT_ADDRESS": repayment_address,
    }

    relayer_service = plan.add_service(
        name="across-relayer",
        config=ServiceConfig(
            image="raveenabhasin/across-mock-relayer:0.0.1",  
            ports={},
            entrypoint=["node", "dist/index.js"],  
            cmd=[],
            env_vars=env_vars,
        ),
        description="Deploys the Across Protocol relayer service for cross-chain operations."
    )

    return relayer_service
    

# # Multi-chain relayer deployment function
# def deploy_multi_chain_relayer_service(plan, chains_config, redis_url, relayer_config={}):
#     """
#     Deploy a multi-chain relayer service
    
#     Args:
#         plan: Kurtosis plan
#         chains_config: List of chain configuration objects
#         redis_url: Redis connection URL
#         relayer_config: Optional relayer configuration (polling_interval, block_range, etc.)
    
#     Example chains_config:
#     [
#         {
#             "chain_id": "1",
#             "name": "ethereum",
#             "rpc": "https://eth-mainnet.g.alchemy.com/v2/your-key",
#             "private_key": "0x...",
#             "spokepool_address": "0x..."
#         },
#         {
#             "chain_id": "42161", 
#             "name": "arbitrum",
#             "rpc": "https://arb-mainnet.g.alchemy.com/v2/your-key",
#             "private_key": "0x...",
#             "spokepool_address": "0x..."
#         }
#     ]
#     """
#     env_vars = {}
    
#     # Add chain-specific environment variables
#     for chain in chains_config:
#         chain_name = chain["name"].upper()
#         env_vars["{}_RPC".format(chain_name)] = chain["rpc"]
#         env_vars["{}_PRIVATE_KEY".format(chain_name)] = chain["private_key"]
#         env_vars["{}_SPOKEPOOL_ADDRESS".format(chain_name)] = chain["spokepool_address"]
    
#     # Add Redis and relayer configuration
#     env_vars["REDIS_URL"] = redis_url
#     env_vars["POLLING_INTERVAL"] = str(relayer_config.get("polling_interval", 5000))
#     env_vars["BLOCK_RANGE"] = str(relayer_config.get("block_range", 100))
#     env_vars["REPAYMENT_CHAIN_ID"] = str(relayer_config.get("repayment_chain_id", 1225280))
#     env_vars["REPAYMENT_ADDRESS"] = relayer_config.get("repayment_address", "0x333F13a6913553EE8C380173B16449d1F7AD0aF9")
    
#     # Create a JSON string of chain configurations for the relayer to parse
#     chains_json = json.encode({
#         chain["chain_id"]: {
#             "rpc": "${{{}}}".format("{}_RPC".format(chain["name"].upper())),
#             "privateKey": "${{{}}}".format("{}_PRIVATE_KEY".format(chain["name"].upper())),
#             "spokePoolAddress": "${{{}}}".format("{}_SPOKEPOOL_ADDRESS".format(chain["name"].upper())),
#             "chainId": int(chain["chain_id"]),
#             "name": chain["name"]
#         }
#         for chain in chains_config
#     })
    
#     env_vars["CHAINS_CONFIG"] = chains_json
    
#     plan.upload_files(
#         src="./relayer",
#         name="relayer-code"
#     )
    
#     relayer_service = plan.add_service(
#         name="multi-chain-across-relayer",
#         config=ServiceConfig(
#             image="node:18-alpine",
#             ports={"api": PortSpec(number=3000, transport_protocol="TCP")},
#             env_vars=env_vars,
#             cmd=["/bin/sh", "-c", "cd /app && npm install && npm run build && npm start"],
#             files={"/app": "relayer-code"}
#         )
#     )
#     return relayer_service

# # Alternative approach: More explicit chain configuration
# def deploy_relayer_with_explicit_chains(plan, ethereum_config, arbitrum_config, optimism_config, base_config, polygon_config, redis_url, relayer_config={}):
#     """
#     Deploy relayer with explicitly named chain configs
#     """
#     chains = [
#         {"chain_id": "1", "name": "ethereum", **ethereum_config},
#         {"chain_id": "42161", "name": "arbitrum", **arbitrum_config}, 
#         {"chain_id": "10", "name": "optimism", **optimism_config},
#         {"chain_id": "8453", "name": "base", **base_config},
#         {"chain_id": "137", "name": "polygon", **polygon_config}
#     ]
    
#     # Filter out None configs (for optional chains)
#     active_chains = [chain for chain in chains if chain.get("rpc") is not None]
    
#     return deploy_multi_chain_relayer_service(plan, active_chains, redis_url, relayer_config)

# # Usage example functions
# def example_usage_1(plan):
#     """Example with dynamic chain list"""
#     chains_config = [
#         {
#             "chain_id": "1",
#             "name": "ethereum", 
#             "rpc": "https://eth-mainnet.g.alchemy.com/v2/your-key",
#             "private_key": "0x1234...",
#             "spokepool_address": "0xabcd..."
#         },
#         {
#             "chain_id": "42161",
#             "name": "arbitrum",
#             "rpc": "https://arb-mainnet.g.alchemy.com/v2/your-key", 
#             "private_key": "0x5678...",
#             "spokepool_address": "0xefgh..."
#         },
#         {
#             "chain_id": "10",
#             "name": "optimism",
#             "rpc": "https://opt-mainnet.g.alchemy.com/v2/your-key",
#             "private_key": "0x9012...", 
#             "spokepool_address": "0xijkl..."
#         }
#     ]
    
#     relayer_config = {
#         "polling_interval": 1000,
#         "block_range": 50,
#         "repayment_chain_id": 1225280,
#         "repayment_address": "0x333F13a6913553EE8C380173B16449d1F7AD0aF9"
#     }
    
#     return deploy_multi_chain_relayer_service(
#         plan, 
#         chains_config, 
#         "redis://redis:6379",
#         relayer_config
#     )

# def example_usage_2(plan):
#     """Example with explicit chain configs"""
#     ethereum_config = {
#         "rpc": "https://eth-mainnet.g.alchemy.com/v2/your-key",
#         "private_key": "0x1234...",
#         "spokepool_address": "0xabcd..."
#     }
    
#     arbitrum_config = {
#         "rpc": "https://arb-mainnet.g.alchemy.com/v2/your-key",
#         "private_key": "0x5678...", 
#         "spokepool_address": "0xefgh..."
#     }
    
#     # Set to None to disable a chain
#     optimism_config = None
#     base_config = None
#     polygon_config = None
    
#     return deploy_relayer_with_explicit_chains(
#         plan,
#         ethereum_config,
#         arbitrum_config, 
#         optimism_config,
#         base_config,
#         polygon_config,
#         "redis://redis:6379"
#     )

# # Helper function to create chain config from individual parameters
# def create_chain_config(chain_id, name, rpc, private_key, spokepool_address):
#     """Helper to create a chain config object"""
#     return {
#         "chain_id": str(chain_id),
#         "name": name,
#         "rpc": rpc, 
#         "private_key": private_key,
#         "spokepool_address": spokepool_address
#     }

# # Backward compatibility function (converts old 2-chain format to new multi-chain)
# def deploy_relayer_service_legacy(plan, chain_a_config, chain_b_config, spokepool_a_address, spokepool_b_address, redis_url):
#     """
#     Legacy function for backward compatibility with 2-chain setup
#     """
#     chains_config = [
#         {
#             "chain_id": str(chain_a_config.chain_id),
#             "name": "chainA",
#             "rpc": chain_a_config.rpc,
#             "private_key": chain_a_config.private_key,
#             "spokepool_address": spokepool_a_address
#         },
#         {
#             "chain_id": str(chain_b_config.chain_id), 
#             "name": "chainB",
#             "rpc": chain_b_config.rpc,
#             "private_key": chain_b_config.private_key,
#             "spokepool_address": spokepool_b_address
#         }
#     ]
    
#     return deploy_multi_chain_relayer_service(plan, chains_config, redis_url)