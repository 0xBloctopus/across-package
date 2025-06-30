// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WETH.sol";
import "../src/MockSpokePool.sol";

contract DeployWETHAndMockSpokePool is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy WETH
        WETH weth = new WETH();
        console.log("WETH deployed at:", address(weth));

        // Deploy MockSpokePool with WETH address
        MockSpokePool spokePool = new MockSpokePool(address(weth));
        console.log("MockSpokePool deployed at:", address(spokePool));

        vm.stopBroadcast();
    }
}