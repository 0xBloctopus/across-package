def deploy_bridge_ui_service(plan, supported_chains):
    """
    Deploys the Bridge UI container with VITE_SUPPORTED_CHAINS passed as an env var

    Args:
        plan: Kurtosis plan
        supported_chains: List of supported chains to be passed as VITE_SUPPORTED_CHAINS

    Returns:
        struct(hostname, port)
    """

    # Encode the chain metadata as a JSON string to pass as env var
    chains_json = json.encode(supported_chains)

    env_vars = {
        "VITE_SUPPORTED_CHAINS": chains_json
    }

    plan.print("chain env")
    plan.print(env_vars)

    bridge_ui_service = plan.add_service(
        name = "bridge-ui",
        config = ServiceConfig(
            image = "raveenabhasin/across-mock-bridge-ui:0.0.7",  
            ports = {
                "ui": PortSpec(number=80, transport_protocol="TCP", wait=None)
            },
            entrypoint = [], 
            cmd = [],
            env_vars = env_vars,
        ),
        description = "Bridge UI service exposing the Across Protocol modal for bridging assets"
    )

    return struct(
        hostname = bridge_ui_service.hostname,
    )