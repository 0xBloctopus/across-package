// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Mock_Adapter} from "../src/Adapter.sol";
import {MockHubPool} from "../src/HubPool.sol";

contract DeployHubPoolAndAdapter is Script {
    function run() public {
        // You can use a private key from env or default to 0
        uint256 deployer = vm.envOr("PRIVATE_KEY", uint256(0));

        vm.startBroadcast(deployer);

        // Deploy the Adapter
        Mock_Adapter adapter = new Mock_Adapter();

        // Deploy the HubPool with the adapter's address
        MockHubPool hubPool = new MockHubPool(address(adapter));

        vm.stopBroadcast();

        console2.log("HubPool deployed at:", address(hubPool));

        // return (address(adapter), address(hubPool));
    }
}