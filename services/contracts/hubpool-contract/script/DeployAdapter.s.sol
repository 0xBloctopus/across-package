// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ethereum_Adapter} from "../lib/contracts/contracts/chain-adapters/Ethereum_Adapter.sol";

contract DeployAdapter is Script {
    function run() public {
        vm.startBroadcast();
        Ethereum_Adapter adapter = new Ethereum_Adapter();
        vm.stopBroadcast();
        console2.log("Contract deployed at: ", address(adapter));
    }
}
