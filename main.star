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
fund_weth_service = import_module("./services/fund_weth.star")

def run(plan, args):
    plan.print("Starting Across Protocol cross-chain simulation...")
    plan.print("Parsing the L1 input args")
    parsed_data = input_parser.input_parser(plan, args)
    plan.print(parsed_data)

    deploy_contract = parsed_data.deploy_contract
    networks = parsed_data.networks
    if deploy_contract:
        # Deploy across all networks, with HubPool only on ethereum_mainnet
        deployed_addresses = {}

        # Identify the hub network (ethereum_mainnet)
        hub_network = None
        for n in networks:
            if n.type == "ethereum_mainnet":
                hub_network = n
                break
        if hub_network == None:
            fail("No network of type 'ethereum_mainnet' found; required for HubPool deployment")

        # First deploy on hub network
        plan.print("Deploying contracts on hub network (ethereum_mainnet): " + hub_network.name)

        hub_weth = deployer.deploy_contract(
            plan,
            "script/DeployWETH.s.sol",
            "DeployWETH",
            hub_network.rpc,
            hub_network.private_key
        )
        plan.print("WETH (hub) at: " + hub_weth)

        lp_token_factory_address = deployer.deploy_contract(
            plan,
            "script/DeployLpTokenFactory.s.sol",
            "DeployLpTokenFactory",
            hub_network.rpc,
            hub_network.private_key
        )
        plan.print("LpTokenFactory at: " + lp_token_factory_address)

        finder_address = deployer.deploy_contract(
            plan,
            "script/DeployFinder.s.sol",
            "DeployFinder",
            hub_network.rpc,
            hub_network.private_key
        )
        plan.print("Finder at: " + finder_address)

        hub_adapter = deployer.deploy_contract(
            plan,
            "script/DeployAdapter.s.sol",
            "DeployAdapter",
            hub_network.rpc,
            hub_network.private_key
        )
        plan.print("Adapter (hub) at: " + hub_adapter)

        hubpool_address = deployer.deploy_contract(
            plan,
            "script/DeployHubPool.s.sol",
            "DeployHubPool",
            hub_network.rpc,
            hub_network.private_key,
            {
                "LP_TOKEN_FACTORY": lp_token_factory_address,
                "FINDER": finder_address,
                "WETH": hub_weth,
            }
        )
        plan.print("HubPool at: " + hubpool_address)

        # Deploy SpokePool on hub network as well
        spokepool_impl_hub = deployer.deploy_contract(
            plan,
            "script/DeploySpokePoolImpl.s.sol",
            "DeploySpokePoolImpl",
            hub_network.rpc,
            hub_network.private_key,
            {
                "WETH": hub_weth,
                "HUBPOOL_ADDRESS": hubpool_address
            }
        )
        plan.print("SpokePool impl (hub) at: " + spokepool_impl_hub)

        spokepool_proxy_hub = deployer.deploy_contract(
            plan,
            "script/DeploySpokePoolProxy.s.sol",
            "DeploySpokePoolProxy",
            hub_network.rpc,
            hub_network.private_key,
            {
                "SPOKEPOOL_IMPL": spokepool_impl_hub.strip(),
                "HUBPOOL_ADDRESS": hubpool_address
            }
        )
        plan.print("SpokePool proxy (hub) at: " + spokepool_proxy_hub)

        deployed_addresses[hub_network.type] = {
            "weth": hub_weth,
            "adapter": hub_adapter,
            "spokePool": spokepool_proxy_hub,
            "hubPool": hubpool_address,
        }

        # Deploy to all non-hub networks
        for n in networks:
            if n.type == hub_network.type:
                continue
            plan.print("Deploying contracts on network: " + n.name + " (" + n.type + ")")

            weth_addr = deployer.deploy_contract(
                plan,
                "script/DeployWETH.s.sol",
                "DeployWETH",
                n.rpc,
                n.private_key
            )
            plan.print("WETH at: " + weth_addr)

            adapter_addr = deployer.deploy_contract(
                plan,
                "script/DeployAdapter.s.sol",
                "DeployAdapter",
                n.rpc,
                n.private_key
            )
            plan.print("Adapter at: " + adapter_addr)

            sp_impl = deployer.deploy_contract(
                plan,
                "script/DeploySpokePoolImpl.s.sol",
                "DeploySpokePoolImpl",
                n.rpc,
                n.private_key,
                {
                    "WETH": weth_addr,
                    "HUBPOOL_ADDRESS": hubpool_address
                }
            )
            plan.print("SpokePool impl at: " + sp_impl)

            sp_proxy = deployer.deploy_contract(
                plan,
                "script/DeploySpokePoolProxy.s.sol",
                "DeploySpokePoolProxy",
                n.rpc,
                n.private_key,
                {
                    "SPOKEPOOL_IMPL": sp_impl.strip(),
                    "HUBPOOL_ADDRESS": hubpool_address
                }
            )
            plan.print("SpokePool proxy at: " + sp_proxy)

            deployed_addresses[n.type] = {
                "weth": weth_addr,
                "adapter": adapter_addr,
                "spokePool": sp_proxy,
            }

        # Register spoke pools for all networks in HubPool
        for n in networks:
            plan.print("Registering spoke for network " + n.type + " (chain_id=" + str(n.chain_id) + ") with HubPool...")
            addrs = deployed_addresses.get(n.type, {})
            adapter_to_register = addrs.get("adapter", "")
            spokepool_to_register = addrs.get("spokePool", "")
            pool_registration.register_spoke_pools(
                plan,
                hub_network.rpc,
                hub_network.private_key,
                hubpool_address,
                n.chain_id,
                adapter_to_register,
                spokepool_to_register,
            )
  
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
        # Prefer deployed addresses if available
        _dyn = {}
        if deploy_contract:
            # Keep in sync with keys in deployed_addresses
            _dyn = deployed_addresses.get(network.type, {})
        chain_config = {
            "chain_id": network.chain_id,
            "type": network.type,  
            "rpc": network.rpc,
            "private_key": network.private_key,
            "spokepool_address": _dyn.get("spokePool", constants.NETWORK_ADDRESSES[network.type]["spokePool"])
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
    # Prefer deployed HubPool on ethereum_mainnet if present
    _hub_addr = None
    if deploy_contract:
        _hub_addr = deployed_addresses.get("ethereum_mainnet", {}).get("hubPool")
    hubpool_config = {
        "rpc": parsed_data.dataworker.hubpool_rpc,
        # "private_key": parsed_data.dataworker.hubpool_private_key,
        "private_key": constants.DATAWORKER_INFO["private_key"],
        "address": _hub_addr if _hub_addr != None and _hub_addr != "" else constants.NETWORK_ADDRESSES[parsed_data.dataworker.network_type]["hubPool"]
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
        _dyn = {}
        if deploy_contract:
            _dyn = deployed_addresses.get(network.type, {})
        chain_info = {
            "name": network.name,
            "chain_id": int(network.chain_id),
            "network_type": network.type,
            "rpc": network.rpc,
            "spokepool_address": _dyn.get("spokePool", constants.NETWORK_ADDRESSES[network.type]["spokePool"]),
            "native_currency": chain_meta["native_currency"],
            "tokens": chain_meta["tokens"],
            "router_address": chain_meta["router_address"]
        }
        supported_chains.append(chain_info)

    bridge_ui = bridge_ui_service.deploy_bridge_ui_service(
        plan,
        supported_chains
    )

    plan.print("Funding relayer with WETH (deposit 10 ETH -> WETH) on all networks...")
    fund_result = fund_weth_service.run_fund_relayer_weth(
        plan=plan,
        networks=supported_chains,
        relayer_private_key=constants.RELAYER_INFO["private_key"],
        amount_eth="10",
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
                spokepool_address = (deployed_addresses.get(network.type, {}).get("spokePool") if deploy_contract else constants.NETWORK_ADDRESSES[network.type].get("spokePool", ""))
            )
            for network in parsed_data.networks
        ],
        "hubpool_address": (_hub_addr if _hub_addr != None and _hub_addr != "" else constants.NETWORK_ADDRESSES[parsed_data.dataworker.network_type]["hubPool"]),
        "relayer_address": constants.RELAYER_INFO["repayment_address"],
        "bridge_ui": struct(
            hostname = bridge_ui.hostname,
        )
    }
    
    output = struct(**output_dict)
    return output
    
   