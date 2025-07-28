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
    
    # weth_address = deployer.deploy_contract(
    #     plan,
    #     "script/DeployWETH.s.sol",
    #     "DeployWETH",
    #     networks[0].rpc,
    #     networks[0].private_key
    # )
    # plan.print("WETH contract at: " + weth_address)

    # lp_token_factory_address = deployer.deploy_contract(
    #     plan,
    #     "script/DeployLpTokenFactory.s.sol",
    #     "DeployLpTokenFactory",
    #     networks[0].rpc,
    #     networks[0].private_key
    # )

    # plan.print("LpTokenFactory contract at: " + lp_token_factory_address)

    # finder_address = deployer.deploy_contract(
    #    plan,
    #     "script/DeployFinder.s.sol",
    #     "DeployFinder",
    #     networks[0].rpc,
    #     networks[0].private_key 
    # )

    # plan.print("Finder contract at: " + finder_address)

    # adapter_address = deployer.deploy_contract(
    #     plan,
    #     "script/DeployAdapter.s.sol",
    #     "DeployAdapter",
    #     networks[0].rpc,
    #     networks[0].private_key
    # )

    # plan.print("Adapter contract at: " + adapter_address)

    # hubpool_address = deployer.deploy_contract(
    #     plan,
    #     "script/DeployHubPool.s.sol",
    #     "DeployHubPool",
    #     networks[0].rpc,
    #     networks[0].private_key,
    #     {
    #         "LP_TOKEN_FACTORY": lp_token_factory_address,
    #         "FINDER": finder_address,
    #         "WETH": weth_address,
    #     }
    # )

    # plan.print("Hubpool contract at: " + hubpool_address)

    # spokepool_impl_address = deployer.deploy_contract(
    #     plan,
    #     "script/DeploySpokePoolImpl.s.sol",
    #     "DeploySpokePoolImpl",
    #     networks[0].rpc,
    #     networks[0].private_key,
    #     {
    #         "WETH": weth_address,
    #         "HUBPOOL_ADDRESS": hubpool_address
    #     }
    # )
    # plan.print("Spokepool impl output: " + spokepool_impl_address)

    # spokepool_proxy = deployer.deploy_contract(
    #     plan,
    #     "script/DeploySpokePoolProxy.s.sol",
    #     "DeploySpokePoolProxy",
    #     networks[0].rpc,
    #     networks[0].private_key,
    #     {
    #         "SPOKEPOOL_IMPL": spokepool_impl_address.strip(),
    #         "HUBPOOL_ADDRESS": hubpool_address
    #     }
    # )
    # plan.print("Spoke pool proxy: " + spokepool_proxy)
    
    # weth_address_b = deployer.deploy_contract(
    #     plan,
    #     "script/DeployWETH.s.sol",
    #     "DeployWETH",
    #     networks[1].rpc,
    #     networks[1].private_key
    # )
    # plan.print("WETH contract at chain B: " + weth_address_b)

    # adapter_address_b = deployer.deploy_contract(
    #     plan,
    #     "script/DeployAdapter.s.sol",
    #     "DeployAdapter",
    #     networks[0].rpc,
    #     networks[0].private_key
    # )

    # plan.print("Adapter contract at: " + adapter_address_b)

    # spokepool_impl_address_b = deployer.deploy_contract(
    #     plan,
    #     "script/DeploySpokePoolImpl.s.sol",
    #     "DeploySpokePoolImpl",
    #     networks[1].rpc,
    #     networks[1].private_key,
    #     {
    #         "WETH": weth_address_b,
    #         "HUBPOOL_ADDRESS": hubpool_address
    #     }
    # )
    # plan.print("Spokepool impl output for chain B: " + spokepool_impl_address_b)

    # spokepool_proxy_b = deployer.deploy_contract(
    #     plan,
    #     "script/DeploySpokePoolProxy.s.sol",
    #     "DeploySpokePoolProxy",
    #     networks[1].rpc,
    #     networks[1].private_key,
    #     {
    #         "SPOKEPOOL_IMPL": spokepool_impl_address_b.strip(),
    #         "HUBPOOL_ADDRESS": hubpool_address
    #     }
    # )
    # plan.print("Spoke pool proxy for chain B: " + spokepool_proxy_b)
    

    # plan.print("Registering spokepool contract on chain a with HubPool...")
    # registration_result_a = pool_registration.register_spoke_pools(
    #     plan,
    #     networks[0].rpc,
    #     networks[0].private_key,
    #     hubpool_address,
    #     networks[0].chain_id,
    #     adapter_address,
    #     spokepool_proxy,
    # )

    # plan.print("Pool registration status: " + str(registration_result_a))

    # plan.print("Registering spokepool contract on chain b with HubPool...")
    # registration_result_b = pool_registration.register_spoke_pools(
    #     plan,
    #     networks[0].rpc,
    #     networks[0].private_key,
    #     hubpool_address,
    #     networks[1].chain_id,
    #     adapter_address_b,
    #     spokepool_proxy_b,
    # )

    # plan.print("Pool registration status: " + str(registration_result_b))
    redis_output = redis.run(
        plan,
        service_name = "redis",
        image = "redis:7",
    )
    redis_url = "redis://{}:{}".format(redis_output.hostname, redis_output.port_number)
    plan.print("Redis running at " + redis_url)
    
    plan.print("Deploying Relayer service...")
    relayer = relayer_service.deploy_relayer_service(
        plan,
        parsed_data.networks[0],
        parsed_data.networks[1], 
        parsed_data.relayer.repayment_address,
        parsed_data.relayer.polling_interval,
        parsed_data.relayer.block_range,
        parsed_data.relayer.private_key,
        redis_url
    )
    
    plan.print("Deploying DataWorker service...")
    dataworker = dataworker_service.deploy_dataworker_service(
        plan,
        parsed_data.dataworker,
        parsed_data.networks[0],
        parsed_data.networks[1],
        redis_url
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
    
   