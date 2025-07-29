ethereum_package = import_module("github.com/ethpandaops/ethereum-package/main.star")
input_parser = import_module("./utils/input_parser.star")
# hub_pool_deployer = import_module("./services/contracts/hubpool_deployer.star")
# spoke_pool_deployer = import_module("./services/contracts/spokepool_deployer.star")
# weth_deployer = import_module("./services/contracts/weth_deployer.star")
# redis = import_module("github.com/kurtosis-tech/redis-package/main.star")
deployer = import_module("./services/contracts/deployer.star")
pool_registration = import_module("./services/contracts/pool_registration.star")
redis = import_module("github.com/kurtosis-tech/redis-package/main.star")
relayer_service = import_module("./services/relayer_service.star")
dataworker_service = import_module("./services/dataworker_service.star")

def run(plan, args):
    plan.print("Starting Across Protocol cross-chain simulation...")
    plan.print("Parsing the L1 input args")
    parsed_data = input_parser.input_parser(plan, args)
    plan.print(parsed_data)
    plan.print("networks")
    plan.print(parsed_data.networks[0].spokepool_address)
    plan.print(parsed_data.networks[1].spokepool_address)
    plan.print("relayer")
    plan.print(parsed_data.relayer)
    plan.print("dataworker")
    plan.print(parsed_data.dataworker)
    
  
    redis_output = redis.run(
        plan,
        service_name = "redis",
        image = "redis:7",
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
            "spokepool_address": network.spokepool_address
        }
        chains_config.append(chain_config)
    
    relayer_config = {
        "polling_interval": parsed_data.relayer.polling_interval,
        "block_range": parsed_data.relayer.block_range,
        "repayment_address": parsed_data.relayer.repayment_address
        # "repayment_chain_id": parsed_data.networks[0].chain_id  # Using first network as repayment chain
    }

    plan.print("Deploying Multi-chain Relayer service...")
    relayer = relayer_service.deploy_multi_chain_relayer_service(
        plan,
        chains_config,
        redis_url,
        relayer_config
    )
    
    # plan.print("Deploying DataWorker service...")
    # dataworker = dataworker_service.deploy_dataworker_service(
    #     plan,
    #     parsed_data.dataworker,
    #     parsed_data.networks[0],
    #     parsed_data.networks[1],
    #     redis_url
    # )

    plan.print("Deploying Multi-chain DataWorker service...")
    
    # Prepare hubpool configuration for dataworker
    hubpool_config = {
        "rpc": parsed_data.dataworker.hubpool_rpc,
        "private_key": parsed_data.dataworker.hubpool_private_key,
        "address": parsed_data.dataworker.hubpool_address
    }
    
    # Prepare dataworker-specific settings
    dataworker_config = {
        "polling_interval": getattr(parsed_data.dataworker, 'polling_interval', 10000),
        "block_range": getattr(parsed_data.dataworker, 'block_range', 100),
        "min_refund_volume": getattr(parsed_data.dataworker, 'min_refund_volume', "0")
    }
    
    dataworker = dataworker_service.deploy_multi_chain_dataworker_service(
        plan,
        chains_config,  # Same chains_config as relayer (without private_key field)
        hubpool_config,
        redis_url,
        dataworker_config
    )

    
    # plan.print("Running end-to-end test...")
    # test_result = e2e_test.run_e2e_test(
    #     plan,
    #     networks,
    #     spokepool_deployment_output["spokepool_address"],
    #     spoke_pool_b_address["spokepool_address"],
    #     weth_deployment_output["weth_address"],
    #     weth_deployment_output_b["weth_address"]
    # )
    
    # plan.print("Across Protocol deployment complete!")
    # plan.print("HubPool: " + hubpool_deployment_output["hubpool_address"])
    # plan.print("SpokePool A: " + spokepool_deployment_output["spokepool_address"])
    # plan.print("SpokePool B: " + spoke_pool_b_address["spokepool_address"])
    # plan.print("Relayer service: across-relayer")
    # plan.print("DataWorker service: across-dataworker")
    # plan.print("Redis: " + redis_url)

    # return output
    
   