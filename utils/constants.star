NETWORK_ADDRESSES = {
    "ethereum_mainnet": {
        "hubPool": "0xc186fA914353c44b2E33eBE05f21846F1048bEda",
        "spokePool": "0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5",
    },
    "arbitrum_mainnet": {
        "spokePool": "0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A",
    },
    "optimism_mainnet": {
        "spokePool": "0x6f26Bf09B1C792e3228e5467807a900A503c0281",
    },
    "base_mainnet": {
        "spokePool": "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64",
    },
    "zksync_mainnet": {
        "spokePool": "0xE0B015E54d54fc84a6cB9B666099c46adE9335FF",
    },
    "polygon_mainnet": {
        "spokePool": "0x9295ee1d8C5b022Be115A2AD3c30C72E34e7F096",
    },
    "bnb_mainnet": {
        "spokePool": "0x4e8E101924eDE233C13e2D8622DC8aED2872d505",
    }
}

CHAIN_METADATA = {
    "ethereum_mainnet": {
        "native_currency": {
            "name": "Ether",
            "symbol": "ETH",
            "decimals": 18,
        },
        "tokens": [
            {
                "symbol": "ETH",
                "name": "Ether",
                "decimals": 18,
                "address": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
            },
            {
                "symbol": "USDC",
                "name": "USD Coin",
                "decimals": 6,
                "address": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
            }
        ],
        "router_address": "",
    },
    "arbitrum_mainnet": {
        "native_currency": {
            "name": "Ether",
            "symbol": "ETH",
            "decimals": 18,
        },
        "tokens": [
            {
                "symbol": "ETH",
                "name": "Ether",
                "decimals": 18,
                "address": "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
            },
            {
                "symbol": "USDC",
                "name": "USD Coin",
                "decimals": 6,
                "address": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
            }
        ],
        "router_address": "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24"
    },
    "base_mainnet": {
        "native_currency": {
            "name": "Ether", 
            "symbol": "ETH",
            "decimals": 18,
        },
        "tokens": [
            {
                "symbol": "ETH",
                "name": "Ether",
                "decimals": 18,
                "address": "0x4200000000000000000000000000000000000006"
            },
            {
                "symbol": "USDC",
                "name": "USD Coin",
                "decimals": 6,
                "address": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
            }
        ],
        "router_address": "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24"
    }
}

RELAYER_INFO = {
    "private_key": "0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31",
    "repayment_address": "0x8943545177806ED17B9F23F0a21ee5948eCaa776",
    "polling_interval": "5000",
    "block_range": "100"
}

DATAWORKER_INFO = {
    "private_key": "0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31",
    "polling_interval": "5000",
    "block_range": "100",
    "min_refund_volume": "0"
}