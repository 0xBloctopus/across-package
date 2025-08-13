ethereum_package = import_module("github.com/ethpandaops/ethereum-package/main.star")
input_parser = import_module("./utils/input_parser.star")
constants = import_module("./utils/constants.star")
# hub_pool_deployer = import_module("./services/contracts/hubpool_deployer.star")
# spoke_pool_deployer = import_module("./services/contracts/spokepool_deployer.star")
# weth_deployer = import_module("./services/contracts/weth_deployer.star")
# redis = import_module("github.com/kurtosis-tech/redis-package/main.star")
deployer = import_module("./services/contracts/deployer.star")
pool_registration = import_module("./services/contracts/pool_registration.star")
redis = import_module("github.com/kurtosis-tech/redis-package/main.star")
relayer_service = import_module("./services/relayer_service.star")
dataworker_service = import_module("./services/dataworker_service.star")
bridge_ui_service = import_module("./services/bridge_ui_service.star")
approve_tokens_service = import_module("./services/approve_tokens.star")
swap_service = import_module("./services/swap_tokens.star")

def run(plan, args):
    plan.print("Starting Across Protocol cross-chain simulation...")
    plan.print("Parsing the L1 input args")
    parsed_data = input_parser.input_parser(plan, args)
    plan.print(parsed_data)
  
    redis_output = redis.run(
        plan,
        service_name = "redis",
        image = "redis:7",
        max_memory=256,
        min_memory=64,
        persistent=False
    )
    redis_url = "redis://{}:{}".format(redis_output.hostname, redis_output.port_number)
    plan.print("Redis running at " + redis_url)
    

    chains_config = []
    for network in parsed_data.networks:
        chain_config = {
            "chain_id": network.chain_id,
            "type": network.type,  
            "rpc": network.rpc,
            "private_key": network.private_key,
            "spokepool_address": constants.NETWORK_ADDRESSES[network.type]["spokePool"]
        }
        chains_config.append(chain_config)
    
    # relayer_config = {
    #     "polling_interval": parsed_data.relayer.polling_interval,
    #     "block_range": parsed_data.relayer.block_range,
    #     "repayment_address": parsed_data.relayer.repayment_address
    #     # "repayment_chain_id": parsed_data.networks[0].chain_id  # Using first network as repayment chain
    # }

    relayer_config = {
        "relayer_private_key": constants.RELAYER_INFO["private_key"],
        "polling_interval": constants.RELAYER_INFO["polling_interval"],
        "block_range": constants.RELAYER_INFO["block_range"],
        "repayment_address": constants.RELAYER_INFO["repayment_address"]
    }

    plan.print("Deploying Relayer service...")
    relayer = relayer_service.deploy_multi_chain_relayer_service(
        plan,
        chains_config,
        redis_url,
        relayer_config
    )

    plan.print("Deploying DataWorker service...")
    
    # Prepare hubpool configuration for dataworker
    hubpool_config = {
        "rpc": parsed_data.dataworker.hubpool_rpc,
        # "private_key": parsed_data.dataworker.hubpool_private_key,
        "private_key": constants.DATAWORKER_INFO["private_key"],
        "address": constants.NETWORK_ADDRESSES[parsed_data.dataworker.network_type]["hubPool"]
    }
    
    # Prepare dataworker-specific settings
    # dataworker_config = {
    #     "polling_interval": getattr(parsed_data.dataworker, 'polling_interval', 10000),
    #     "block_range": getattr(parsed_data.dataworker, 'block_range', 100),
    #     "min_refund_volume": getattr(parsed_data.dataworker, 'min_refund_volume', "0")
    # }
    dataworker_config = {
        "polling_interval": constants.DATAWORKER_INFO["polling_interval"],
        "block_range": constants.DATAWORKER_INFO["block_range"],
        "min_refund_volume": constants.DATAWORKER_INFO["min_refund_volume"]
    }
    
    dataworker = dataworker_service.deploy_multi_chain_dataworker_service(
        plan,
        chains_config,  # Same chains_config as relayer (without private_key field)
        hubpool_config,
        redis_url,
        dataworker_config
    )

    supported_chains = []
    for network in parsed_data.networks:
        chain_meta = constants.CHAIN_METADATA[network.type]
        chain_info = {
            "name": network.name,
            "chain_id": int(network.chain_id),
            "network_type": network.type,
            "rpc": network.rpc,
            "spokepool_address": constants.NETWORK_ADDRESSES[network.type]["spokePool"],
            "native_currency": chain_meta["native_currency"],
            "tokens": chain_meta["tokens"],
            "router_address": chain_meta["router_address"]
        }
        supported_chains.append(chain_info)

    bridge_ui = bridge_ui_service.deploy_bridge_ui_service(
        plan,
        supported_chains
    )

    plan.print("Swap ETH for USDC for relayer...")
    swap_result = swap_service.run_eth_to_usdc_swaps(
        plan=plan,
        networks=supported_chains,
        relayer_private_key=constants.RELAYER_INFO["private_key"],
    )

    plan.print("Running token approvals...")
    approval_result = approve_tokens_service.run_eth_usdc_token_approval_script(
        plan=plan,
        networks=supported_chains,
        relayer_private_key=constants.RELAYER_INFO["private_key"],
    )
    
    output_dict = {
        "chains": [
            struct(
                network_type = network.type,
                chain_id = network.chain_id,
                spokepool_address = constants.NETWORK_ADDRESSES[network.type].get("spokePool", "")
            )
            for network in parsed_data.networks
        ],
        "hubpool_address": constants.NETWORK_ADDRESSES[parsed_data.dataworker.network_type]["hubPool"],
        "relayer_address": constants.RELAYER_INFO["repayment_address"],
        "bridge_ui": struct(
            hostname = bridge_ui.hostname,
        )
    }
    
    output = struct(**output_dict)
    return output
    
   