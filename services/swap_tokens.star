# services/swap_tokens.star

def _get_token_addr(tokens, symbol):
    for t in tokens or []:
        if t.get("symbol") == symbol:
            addr = t.get("address")
            if not addr:
                fail("Token '%s' found but missing 'address' field" % symbol)
            return addr
    fail("Token '%s' not found in provided 'tokens'" % symbol)

def run_eth_to_usdc_swaps(
        plan,
        networks,                   # pass the 'supported_chains' list from main.star
        relayer_private_key,
        amount_eth = "2",
        min_usdc = "0",
        deadline_secs = 600,
        to_address = None,
        script_path_local = "swap_weth_to_usdc.sh",
    ):
    """
    Execute multi-chain ETH->USDC swaps using Foundry's `cast`.

    Skips ethereum_mainnet automatically.

    NETWORK_CONFIGS_SWAP format (comma-separated):
        "rpc|weth|usdc|router,rpc|weth|usdc|router,..."
    """

    entries = []
    for n in networks:
        plan.print("network info")
        plan.print(n)
        # Skip Ethereum mainnet
        if n.get("network_type") == "ethereum_mainnet":
            plan.print("Skipping ETH->USDC swap for ethereum_mainnet")
            continue

        rpc = n.get("rpc")
        if not rpc:
            fail("Each supported_chains item must include 'rpc'")

        tokens = n.get("tokens", [])
        weth = _get_token_addr(tokens, "ETH")
        usdc = _get_token_addr(tokens, "USDC")

        router = n.get("router_address")

        if not router:
            fail("router_address missing on supported_chains item for '%s' (network_type='%s')"
                 % (n.get("name"), n.get("network_type")))

        entries.append("%s|%s|%s|%s" % (rpc, weth, usdc, router))

    if not entries:
        plan.print("No eligible networks for ETH->USDC swap.")
        return {
            "chains_count": 0,
            "eth_amount": str(amount_eth),
            "target_address": to_address or "derived-from-private-key",
            "swap_services": [],
        }

    network_configs_swap = ",".join(entries)

    # Upload the multi-chain swap shell script
    # script_artifact = plan.upload_files(
    #     name = "swap-weth-usdc-script",
    #     src = script_path_local,
    #     description = "Multi-chain swap ETH->USDC via Uniswap V2 using cast",
    # )

    env_vars = {
        "RELAYER_PRIVATE_KEY": relayer_private_key,
        "NETWORK_CONFIGS_SWAP": network_configs_swap,
        "AMOUNT_ETH": str(amount_eth),
        "MIN_USDC": str(min_usdc),
        "DEADLINE_SECS": str(deadline_secs),
    }
    if to_address != None:
        env_vars["TO"] = to_address

    
    script_artifact = plan.upload_files(
        name = "swap-eth-usdc-multi-script",
        src = "swap_weth_to_usdc.sh",  
        description = "Multi-chain swap ETH->USDC via Uniswap V2 using cast",
    )

    result = plan.run_sh(
        name = "run-eth-to-usdc-swaps",
        description = "Execute ETH->USDC swaps via Uniswap V2 using cast",
        image = "raveenabhasin/across-mock-contracts:0.0.9",
        files = { "/scripts": script_artifact },
        env_vars = {
            "RELAYER_PRIVATE_KEY": relayer_private_key,
            "NETWORK_CONFIGS_SWAP": network_configs_swap, 
            "AMOUNT_ETH": str(amount_eth),
            "MIN_USDC": str(min_usdc),
            "DEADLINE_SECS": str(deadline_secs),
            # "TO": to_address,  # optional
        },
        run =
        "bash -lc "
        + "\"set -euo pipefail; "
        + "echo '=== /scripts listing ==='; ls -l /scripts; "
        + "chmod +x /scripts/; "
        + "sed -i 's/\\r$//' /scripts/swap_weth_to_usdc.sh; "
        + "/scripts/swap_weth_to_usdc.sh \\\"$AMOUNT_ETH\\\" \\\"$MIN_USDC\\\" \\\"$DEADLINE_SECS\\\"\""
    )

    plan.print("ETH->USDC Swap Script Output:")
    plan.print(result.output)

    return {
        "chains_count": len(entries),
        "eth_amount": str(amount_eth),
        "target_address": to_address or "derived-from-private-key",
        "swap_services": [{
            "name": "run-eth-to-usdc-swaps",
            "result_exit_code": getattr(result, "exit_code", None),
        }],
    }