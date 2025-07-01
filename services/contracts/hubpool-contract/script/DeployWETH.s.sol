// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WETH.sol";

contract DeployWETH is Script {
    function run() external {
        vm.startBroadcast();
        new WETH();
        vm.stopBroadcast();
    }
}