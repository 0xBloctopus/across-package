def run_eth_usdc_token_approval_script(
    plan,
    networks,                      # pass your supported_chains here
    relayer_private_key,
    eth_approval_wei = "1000000000000000000000",   # 1000 ETH
    usdc_approval_tokens = "1000",                 # 1000 USDC (whole tokens; script converts to 6dp)
    script_path_local = "approve_tokens_multi.sh",
    image = "raveenabhasin/across-mock-contracts:0.0.9",
):
    """
    Approves WETH (ETH) first, then USDC for each network.
    NETWORK_CONFIGS_APPROVAL entry: 'rpc|spokepool|weth|usdc'
    """

    def _find_token(tokens, symbol):
        for t in tokens or []:
            if t.get("symbol") == symbol:
                return t.get("address")
        return None

    entries = []
    for n in networks:
        rpc = n.get("rpc")
        spokepool = n.get("spokepool_address")
        tokens = n.get("tokens", [])
        weth = _find_token(tokens, "ETH")
        usdc = _find_token(tokens, "USDC")

        if not (rpc and spokepool and weth):
            plan.print("Skipping network (missing rpc/spoke/ETH): %s" % (n.get("name") or n.get("network_type")))
            continue

        # USDC may be optional on some nets; script handles empty by skipping
        usdc_addr = usdc or "0x0000000000000000000000000000000000000000"
        entries.append("%s|%s|%s|%s" % (rpc, spokepool, weth, usdc_addr))

    if not entries:
        plan.print("No eligible networks for approvals.")
        return None

    network_configs_env = ",".join(entries)

    script_artifact = plan.upload_files(
        name = "approve-tokens-multi-script",
        src = script_path_local,
        description = "Approve WETH then USDC for each network",
    )

    env_vars = {
        "RELAYER_PRIVATE_KEY": relayer_private_key,
        "NETWORK_CONFIGS_APPROVAL": network_configs_env,
        "ETH_APPROVAL_WEI": str(eth_approval_wei),
        "USDC_APPROVAL_TOKENS": str(usdc_approval_tokens),
    }

    result = plan.run_sh(
        name = "run-eth-usdc-token-approvals",
        description = "Approve WETH and USDC on all configured networks",
        image = image,
        files = { "/scripts": script_artifact },
        env_vars = env_vars,
        run = "bash -lc "
              + "\"echo '=== /scripts listing ==='; ls -l /scripts; "
              + "chmod +x /scripts/approve_tokens_multi.sh; "
              + "sed -i 's/\\r$//' /scripts/approve_tokens_multi.sh; "
              + "/scripts/approve_tokens_multi.sh\"",
    )

    plan.print("ETH/USDC Token Approval Script Output:")
    plan.print(result.output)
    return result
