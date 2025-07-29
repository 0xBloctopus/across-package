// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Ethereum_SpokePool} from "../lib/contracts/contracts/Ethereum_SpokePool.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeploySpokePoolImpl is Script {
    function run() external {

        uint256 deployer = vm.envUint("PRIVATE_KEY");
        address wethAddr = vm.envAddress("WETH");
        
        vm.startBroadcast(deployer);

        // 1. Deploy implementation
        Ethereum_SpokePool implementation = new Ethereum_SpokePool(
            wethAddr, // address of WETH on this chain
            3600, // uint32
            6*3600 // uint32
        );

        vm.stopBroadcast();

        console2.log("Contract deployed at: ", address(implementation));
    }
}