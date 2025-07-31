REQUIRED_NETWORK_FIELDS = [
    "type",
    "chain_id",
    "rpc",
    "private_key",
]

REQUIRED_RELAYER_FIELDS = [
    # "private_key",
    # "polling_interval",
    # "block_range",
    # "repayment_address",
]

REQUIRED_DATAWORKER_FIELDS = [
    "network_type",
    "chain_id",
    # "hubpool_private_key",
    "hubpool_rpc"
]

def input_parser(plan, input_args):
    if "networks" not in input_args:
        fail("Input must contain 'networks' field.")
    # if "relayer" not in input_args:
    #     fail("Input must contain 'relayer' field.")
    if "dataworker" not in input_args:
        fail("Input must contain 'dataworker' field.")

    networks = input_args["networks"]
    # if len(networks) < 2:
    #     fail("At least two networks must be specified.")
    # relayer = input_args["relayer"]
    dataworker = input_args["dataworker"]

    parsed_networks = []
    for idx, network in enumerate(networks):
        # Validate required fields
        for field in REQUIRED_NETWORK_FIELDS:
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
            description = "Validating RPC connectivity for network %s" % network["type"]
        )

        plan.verify(
            value = result.output,
            assertion = "==",
            target_value = expected_chain_id,
            description = "Verifying chain id for network %s" % network["type"]
        )

        plan.print("RPC verification passed for network '%s' (chain id: %s)" % (network["type"], result.output))

        parsed_networks.append(struct(
            type = network["type"],
            chain_id = network["chain_id"],
            rpc = network["rpc"],
            private_key = network["private_key"],
        ))

    # Validate relayer fields
    # for field in REQUIRED_RELAYER_FIELDS:
    #     if field not in relayer:
    #         fail("Relayer config missing required field '%s'." % field)

    # parsed_relayer = struct(
    #     private_key = relayer["private_key"],
    #     polling_interval = relayer["polling_interval"],
    #     block_range = relayer["block_range"],
    #     repayment_address = relayer["repayment_address"]
    # )

    # Validate dataworker fields
    for field in REQUIRED_DATAWORKER_FIELDS:
        if field not in dataworker:
            fail("Dataworker config missing required field '%s'." % field)

    parsed_dataworker = struct(
        network_type = dataworker["network_type"],
        chain_id = dataworker["chain_id"],
        # hubpool_private_key = dataworker["hubpool_private_key"],
        hubpool_rpc = dataworker["hubpool_rpc"]
    )

    return struct(
        networks = parsed_networks,
        # relayer = parsed_relayer,
        dataworker = parsed_dataworker
    )