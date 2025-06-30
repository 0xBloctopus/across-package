REQUIRED_FIELDS = [
    "name",
    "rpc",
    "private_key",
]

OPTIONAL_FIELDS = [
    "endpoint",
    "trusted_send_lib",
    "trusted_receive_lib",
    "eid",
    "chain_id",
]

def input_parser(plan, input_args):
    if "networks" not in input_args:
        fail("Input must contain 'networks' field.")

    networks = input_args["networks"]
    # if len(networks) < 2:
    #     fail("At least two networks must be specified.")

    parsed_networks = []

    for idx, network in enumerate(networks):
        # Validate required fields
        for field in REQUIRED_FIELDS:
            if field not in network:
                fail("Network %d is missing required field '%s'." % (idx, field))

        rpc_url = network["rpc"]
        expected_chain_id = network["chain_id"]

        command = "curl -s -X POST -H \"Content-Type: application/json\" -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[],\"id\":1}' %s | jq -r '.result' | tr -d '\\n' | xargs printf '%%d'" % rpc_url

        result = plan.run_sh(
            run = command,
            name = "curl-job-%d" % idx,
            image = "badouralix/curl-jq",
            wait = "180s",
            description = "Validating RPC connectivity for network %s" % network["name"]
        )

        # Verify that the chain id matches the expected value using plan.verify
        plan.verify(
            value = result.output,
            assertion = "==",
            target_value = expected_chain_id,
            description = "Verifying chain id for network %s" % network["name"]
        )

        plan.print("RPC verification passed for network '%s' (chain id: %s)" % (network["name"], result.output))

        parsed_networks.append(struct(
            name = network["name"],
            chain_id = network["chain_id"],
            rpc = network["rpc"],
            private_key = network["private_key"]
        ))

    return parsed_networks