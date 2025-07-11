// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Store} from "../lib/protocol/packages/core/contracts/oracle/implementation/Store.sol";
import {FixedPoint} from "../lib/protocol/packages/core/contracts/common/implementation/FixedPoint.sol";

contract DeployStore is Script {
    function run() public {
        vm.startBroadcast();
        FixedPoint.Unsigned memory oracleFee = FixedPoint.Unsigned({ rawValue: 1e12 }); // e.g. 0.000001
        FixedPoint.Unsigned memory delayFee = FixedPoint.Unsigned({ rawValue: 5e11 });  // e.g. 0.0000005

        address timer = address(0); // Replace with a real Timer contract address if needed


        Store store = new Store(oracleFee, delayFee, timer);        vm.stopBroadcast();
        console2.log("Contract deployed at: ", address(store));
    }
}