// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeploySpokePoolProxy is Script {
    function run() external {
        uint256 deployer = vm.envUint("PRIVATE_KEY");
        address implementation = vm.envAddress("SPOKEPOOL_IMPL");
        address hubPool = vm.envAddress("HUBPOOL_ADDRESS");

        vm.startBroadcast(deployer);

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(uint32,address)",
            1_000_000, // initialDepositId
            hubPool     // withdrawalRecipient
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        vm.stopBroadcast();

        console2.log("Contract deployed at: ", address(proxy));
    }
}