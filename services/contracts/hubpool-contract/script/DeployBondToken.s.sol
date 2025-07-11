// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {BondToken} from "../src/BondToken.sol";

contract DeployBondToken is Script {
    function run() public {
        vm.startBroadcast();

        BondToken bondToken = new BondToken();
        vm.stopBroadcast();
        console2.log("Contract deployed at: ", address(bondToken));
    }
}