// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WETH.sol";
import "../src/MockSpokePool.sol";

contract DeployWETHAndMockSpokePool is Script {
    function run() external {
        address weth = vm.envOr("WETH_ADDRESS", address(0));

        vm.startBroadcast(vm.envOr("PRIVATE_KEY", uint256(0)));

        MockSpokePool spokePool = new MockSpokePool(weth);
        console.log("MockSpokePool deployed at:", address(spokePool));

        vm.stopBroadcast();
    }
}