def run_fund_relayer_weth(
    plan,
    networks,                 
    relayer_private_key,
    amount_eth = "10",       
    image = "raveenabhasin/across-mock-contracts:0.0.9",
):
    """
    For each network, call WETH.deposit() with the given ETH amount using the relayer's private key.
    Skips networks missing ETH token address.
    """

    def _find_token(tokens, symbol):
        for t in tokens or []:
            if t.get("symbol") == symbol:
                return t.get("address")
        return None

    results = []
    for n in networks:
        rpc = n.get("rpc")
        tokens = n.get("tokens", [])
        weth = _find_token(tokens, "ETH")

        if not (rpc and weth):
            plan.print("Skipping WETH funding (missing rpc/ETH) for %s" % (n.get("name") or n.get("network_type")))
            continue

        cmd = (
            "cast send " + weth + " \"deposit()\" --value " + str(amount_eth) + "ether "
            + "--private-key $RELAYER_PRIVATE_KEY --rpc-url '" + rpc + "'"
        )

        plan.print("Funding WETH for network: " + (n.get("name") or n.get("network_type")))
        res = plan.run_sh(
            name = "fund-weth-" + (n.get("network_type") or "unknown"),
            description = "Deposit ETH into WETH for relayer",
            image = image,
            env_vars = { "RELAYER_PRIVATE_KEY": relayer_private_key },
            run = cmd.strip(),
        )
        results.append({
            "network": n.get("network_type"),
            "exit_code": getattr(res, "exit_code", None),
            "output": getattr(res, "output", ""),
        })

    return { "results": results }


