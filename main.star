# ethereum_package = import_module("github.com/LZeroAnalytics/ethereum-package/main.star")
ethereum_package = import_module("github.com/ethpandaops/ethereum-package/main.star")
input_parser = import_module("./utils/input_parser.star")
hub_pool_deployer = import_module("./services/contracts/hubpool_deployer.star")
spoke_pool_deployer = import_module("./services/contracts/spokepool_deployer.star")
weth_deployer = import_module("./services/contracts/weth_deployer.star")

def run(plan, args):
    plan.print("Starting Across Protocol cross-chain simulation...")
    plan.print("Parsing the L1 input args")
    networks = input_parser.input_parser(plan, args)
    plan.print("networks")
    plan.print(networks)
    
    plan.print("Deploying WETH on Chain A...")
    weth_deployment_output = weth_deployer.deploy_weth(plan, networks[0].rpc, networks[0].private_key)
    plan.print(weth_deployment_output["weth_address"])
    
    plan.print("Deploying Spoke Pool on Chain A...")
    spokepool_deployment_output = spoke_pool_deployer.deploy_spokepool(plan, networks[0].rpc, networks[0].private_key, weth_deployment_output["weth_address"])
    plan.print(spokepool_deployment_output["spokepool_address"])
    
   