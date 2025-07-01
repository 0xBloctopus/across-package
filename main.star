ethereum_package = import_module("github.com/ethpandaops/ethereum-package/main.star")
input_parser = import_module("./utils/input_parser.star")
hub_pool_deployer = import_module("./services/contracts/hubpool_deployer.star")
spoke_pool_deployer = import_module("./services/contracts/spokepool_deployer.star")
weth_deployer = import_module("./services/contracts/weth_deployer.star")
redis = import_module("github.com/kurtosis-tech/redis-package/main.star")

def run(plan, args):
    plan.print("Starting Across Protocol cross-chain simulation...")
    plan.print("Parsing the L1 input args")
    networks = input_parser.input_parser(plan, args)
    plan.print("networks")
    plan.print(networks)
    
    plan.print("Deploying Hub Pool contract on Chain A...")
    output = hub_pool_deployer.deploy_hub_pool_and_adapter(plan, networks[0].rpc, networks[0].private_key)
    plan.print("output")
    plan.print(output["hubpool_address"])

    plan.print("Deploying WETH on Chain A...")
    weth_deployment_output = weth_deployer.deploy_weth(plan, networks[0].rpc, networks[0].private_key)
    plan.print(weth_deployment_output["weth_address"])
    
    plan.print("Deploying Spoke Pool on Chain A...")
    spokepool_deployment_output = spoke_pool_deployer.deploy_spokepool(plan, networks[0].rpc, networks[0].private_key, weth_deployment_output["weth_address"])
    plan.print(spokepool_deployment_output["spokepool_address"])

    plan.print("Deploying WETH on Chain B...")
    weth_deployment_output_b = weth_deployer.deploy_weth(plan, networks[1].rpc, networks[1].private_key)
    plan.print(weth_deployment_output_b["weth_address"])
    
    plan.print("Deploying Spoke Pool on Chain B...")
    spoke_pool_b_address = spoke_pool_deployer.deploy_spokepool(plan, networks[1].rpc, networks[1].private_key, weth_deployment_output_b["weth_address"])
    
    plan.print("Starting Redis for inter-service communication...")
    redis_output = redis.run(plan, service_name="across-redis", image="redis:7")
    redis_url = "redis://{}:{}".format(redis_output.hostname, redis_output.port_number)
    plan.print("Redis running at " + redis_url)

    pool_registration = import_module("./services/contracts/pool_registration.star")
    relayer_service = import_module("./services/relayer_service.star")
    dataworker_service = import_module("./services/dataworker_service.star")
    e2e_test = import_module("./services/testing/e2e_test.star")
    
    plan.print("Initializing SpokePool contracts...")
    spokepool_a_init = spoke_pool_deployer.initialize_spokepool(
        plan, 
        networks[0].rpc, 
        networks[0].private_key, 
        spokepool_deployment_output["spokepool_address"],
        output["hubpool_address"]
    )
    
    spokepool_b_init = spoke_pool_deployer.initialize_spokepool(
        plan,
        networks[1].rpc,
        networks[1].private_key, 
        spoke_pool_b_address["spokepool_address"],
        output["hubpool_address"]
    )
    
    plan.print("Registering SpokePool contracts with HubPool...")
    registration_result = pool_registration.register_spoke_pools(
        plan,
        networks[0].rpc,
        networks[0].private_key,
        output["hubpool_address"],
        networks[0].chain_id,
        spokepool_deployment_output["spokepool_address"],
        networks[1].chain_id,
        spoke_pool_b_address["spokepool_address"]
    )
    
    plan.print("Deploying Relayer service...")
    relayer = relayer_service.deploy_relayer_service(
        plan,
        networks[0],
        networks[1], 
        spokepool_deployment_output["spokepool_address"],
        spoke_pool_b_address["spokepool_address"],
        redis_url
    )
    
    plan.print("Deploying DataWorker service...")
    dataworker = dataworker_service.deploy_dataworker_service(
        plan,
        networks[0],
        networks[0],
        networks[1],
        output["hubpool_address"],
        spokepool_deployment_output["spokepool_address"],
        spoke_pool_b_address["spokepool_address"],
        redis_url
    )
    
    plan.print("Running end-to-end test...")
    test_result = e2e_test.run_e2e_test(
        plan,
        networks,
        spokepool_deployment_output["spokepool_address"],
        spoke_pool_b_address["spokepool_address"],
        weth_deployment_output["weth_address"],
        weth_deployment_output_b["weth_address"]
    )
    
    plan.print("Across Protocol deployment complete!")
    plan.print("HubPool: " + output["hubpool_address"])
    plan.print("SpokePool A: " + spokepool_deployment_output["spokepool_address"])
    plan.print("SpokePool B: " + spoke_pool_b_address["spokepool_address"])
    plan.print("Relayer service: across-relayer")
    plan.print("DataWorker service: across-dataworker")
    plan.print("Redis: " + redis_url)

    return output
    
   