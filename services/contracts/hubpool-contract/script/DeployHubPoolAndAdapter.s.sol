// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Mock_Adapter} from "../src/Adapter.sol";
import {MockHubPool} from "../src/HubPool.sol";

contract DeployHubPoolAndAdapter is Script {
    function run() public {
        // Get private key from environment variable
        uint256 deployer = vm.envUint("PRIVATE_KEY");

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
