// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Finder} from "../lib/protocol/packages/core/contracts/oracle/implementation/Finder.sol";

contract DeployFinder is Script {
    function run() public {
        vm.startBroadcast();

        Finder finder = new Finder();
        vm.stopBroadcast();
        console2.log("Contract deployed at: ", address(finder));
    }
}