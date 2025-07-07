// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {HubPool} from "../lib/contracts/contracts/HubPool.sol";
import {LpTokenFactory} from "../src/LpTokenFactory.sol";
import {WETH} from "../src/WETH.sol";
import {LpTokenFactoryInterface} from "../lib/contracts/contracts/interfaces/LpTokenFactoryInterface.sol";
// import {FinderInterface} from "../lib/protocol/packages/core/contracts/oracle/interfaces/FinderInterface.sol";
import {FinderInterface} from "@uma/core/contracts/data-verification-mechanism/interfaces/FinderInterface.sol";
import {WETH9Interface} from "../lib/contracts/contracts/external/interfaces/WETH9Interface.sol";


contract DeployHubPool is Script {
    function run() public {
        uint256 deployer = vm.envUint("PRIVATE_KEY");
        address lpTokenFactoryAddr = vm.envAddress("LP_TOKEN_FACTORY");
        address finderAddr = vm.envAddress("FINDER");
        address wethAddr = vm.envAddress("WETH");
        
        vm.startBroadcast(deployer);

        HubPool hubPool = new HubPool(
            LpTokenFactoryInterface(lpTokenFactoryAddr),
            FinderInterface(finderAddr),
            WETH9Interface(wethAddr),
            address(0)
        );

        vm.stopBroadcast();

        console2.log("Contract deployed at: ",address(hubPool));
    }
}