// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AddressWhitelist} from "../lib/protocol/packages/core/contracts/common/implementation/AddressWhitelist.sol";

contract DeployAddressWhitelist is Script {
    function run() public {
        vm.startBroadcast();

        AddressWhitelist addressWhitelist = new AddressWhitelist();
        vm.stopBroadcast();
        console2.log("Contract deployed at: ", address(addressWhitelist));
    }
}