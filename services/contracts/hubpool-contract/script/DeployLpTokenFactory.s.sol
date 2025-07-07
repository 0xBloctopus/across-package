// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LpTokenFactory} from "../src/LpTokenFactory.sol";

contract DeployLpTokenFactory is Script {
    function run() public {
        vm.startBroadcast();

        LpTokenFactory lpTokenFactory = new LpTokenFactory();
        vm.stopBroadcast();
        console2.log("Contract deployed at: ",address(lpTokenFactory));
    }
}