# def deploy_contract(plan, script_path, contract_name, rpc_url, private_key, env_vars=None):
#     env_vars = env_vars or {}
#     env_vars.update({
#         "RPC_URL": rpc_url,
#         "PRIVATE_KEY": private_key,
#     })
#     script_full = script_path + ":" + contract_name

#     if contract_name == "DeploySpokePoolProxy":
#         cmd = (
#             "forge script " + script_full +
#             " --broadcast --json --skip-simulation --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 " 
#             # "| grep -o '0x[a-fA-F0-9]\\{40\\}' | tail -n 1"
#         )
#     else:
#        cmd = (
#             "forge script " + script_full +
#             " --broadcast --json --skip-simulation --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 " +
#             "| grep -o '0x[a-fA-F0-9]\\{40\\}' | tail -n 1"
#         ) 

    
#     deployment = plan.run_sh(
#         name="generic-deployer",
#         description="Deploying " + script_full,
#         image="across-mock-contracts:0.0.7",
#         env_vars=env_vars,
#         run=cmd.strip()
#     )
#     # plan.print("deployment output")
#     # plan.print(deployment)
#     return deployment.output.strip()

def deploy_contract(plan, script_path, contract_name, rpc_url, private_key, env_vars=None):
    env_vars = env_vars or {}
    env_vars.update({
        "RPC_URL": rpc_url,
        "PRIVATE_KEY": private_key,
    })
    script_full = script_path + ":" + contract_name

    # if contract_name == "DeploySpokePoolImpl":
    #    cmd = (
    #         "forge script " + script_full +
    #         " --broadcast --json --skip-simulation --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 " +
    #         "| grep 'Contract deployed at: ' | grep -o '0x[a-fA-F0-9]\\{40\\}' | head -n 1 | tr -d '\\n'"
    #     ) 
    # else:
    cmd = (
        "forge script " + script_full +
        " --broadcast --json --skip-simulation --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 " +
        "| grep 'Contract deployed at: ' | grep -o '0x[a-fA-F0-9]\\{40\\}' | head -n 1 | tr -d '\\n'"
    )
    # else:
    #     cmd = (
    #         "forge script " + script_full +
    #         " --broadcast --json --skip-simulation --via-ir --rpc-url $RPC_URL --private-key $PRIVATE_KEY 2>&1 " +
    #         "| grep 'contract_address' | jq -r '.contract_address' | tr -d '\n'"
    #     )

    deployment = plan.run_sh(
        name="generic-deployer",
        description="Deploying " + script_full,
        image="across-mock-contracts:0.0.8",
        env_vars=env_vars,
        run=cmd.strip()
    )

    plan.print("Deployment output (address extraction):")
    plan.print(deployment.output)

    return deployment.output.strip()