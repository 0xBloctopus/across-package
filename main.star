# ethereum_package = import_module("github.com/LZeroAnalytics/ethereum-package/main.star")
ethereum_package = import_module("github.com/ethpandaops/ethereum-package/main.star")
input_parser = import_module("./utils/input_parser.star")
hub_pool_deployer = import_module("./services/contracts/contract_deployer.star")

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
  
    
    return struct(
        hub_pool_address = output["hubpool_address"],
    )
