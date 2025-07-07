// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WETH.sol";

contract DeployWETH is Script {
    function run() external {
        vm.startBroadcast();
        WETH weth_address = new WETH();
        vm.stopBroadcast();
        console2.log("Contract deployed at: ", address(weth_address));
    }
}