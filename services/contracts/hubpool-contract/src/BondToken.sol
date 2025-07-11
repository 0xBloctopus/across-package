// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


contract BondToken is ERC20 {
    constructor() ERC20("BondToken", "BTK") {
        _mint(msg.sender, 1_000_000*10**decimals());
    }
}