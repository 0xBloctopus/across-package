// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

contract MockSpokePool {
    uint256 public numberOfDeposits;
    address public crossDomainAdmin;
    address public hubPool;
    address public wethAddress;
    
    struct Deposit {
        address depositor;
        address recipient;
        address originToken;
        uint256 amount;
        uint256 destinationChainId;
        uint256 relayerFeePct;
        uint32 quoteTimestamp;
        bytes message;
        uint256 maxCount;
    }
    
    mapping(uint256 => Deposit) public deposits;
    
    event FundsDeposited(
        uint256 indexed depositId,
        uint256 indexed destinationChainId,
        address indexed depositor,
        address recipient,
        address originToken,
        uint256 amount,
        uint256 relayerFeePct,
        uint32 quoteTimestamp
    );
    
    event FilledRelay(
        uint256 indexed depositId,
        uint256 indexed originChainId,
        address indexed relayer,
        address recipient,
        address destinationToken,
        uint256 amount,
        uint256 relayerFeePct
    );
    
    constructor(
        uint256 _initialDepositId,
        address _crossDomainAdmin,
        address _hubPool,
        address _wethAddress
    ) {
        numberOfDeposits = _initialDepositId;
        crossDomainAdmin = _crossDomainAdmin;
        hubPool = _hubPool;
        wethAddress = _wethAddress;
    }
    
    function deposit(
        address recipient,
        address originToken,
        uint256 amount,
        uint256 destinationChainId,
        uint256 relayerFeePct,
        uint32 quoteTimestamp,
        bytes memory message,
        uint256 maxCount
    ) external payable {
        uint256 depositId = numberOfDeposits++;
        
        deposits[depositId] = Deposit({
            depositor: msg.sender,
            recipient: recipient,
            originToken: originToken,
            amount: amount,
            destinationChainId: destinationChainId,
            relayerFeePct: relayerFeePct,
            quoteTimestamp: quoteTimestamp,
            message: message,
            maxCount: maxCount
        });
        
        emit FundsDeposited(
            depositId,
            destinationChainId,
            msg.sender,
            recipient,
            originToken,
            amount,
            relayerFeePct,
            quoteTimestamp
        );
    }
    
    function fillRelay(
        uint256 depositId,
        uint256 originChainId,
        address recipient,
        address destinationToken,
        uint256 amount,
        uint256 relayerFeePct
    ) external {
        emit FilledRelay(
            depositId,
            originChainId,
            msg.sender,
            recipient,
            destinationToken,
            amount,
            relayerFeePct
        );
    }
}

contract DeploySpokePool is Script {
    function run() external {
        vm.startBroadcast();
        
        uint256 initialDepositId = vm.envUint("INITIAL_DEPOSIT_ID");
        address crossDomainAdmin = vm.envAddress("CROSS_DOMAIN_ADMIN");
        address hubPool = vm.envAddress("HUB_POOL");
        address wethAddress = vm.envAddress("WETH_ADDRESS");
        
        MockSpokePool spokePool = new MockSpokePool(
            initialDepositId,
            crossDomainAdmin,
            hubPool,
            wethAddress
        );
        
        console.log("Contract deployed at:", address(spokePool));
        
        vm.stopBroadcast();
    }
}
