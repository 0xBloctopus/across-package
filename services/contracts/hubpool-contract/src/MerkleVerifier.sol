// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MerkleVerifier {
    function verifyProof(bytes32 root, bytes32[] calldata proof, bytes32 leaf) external pure returns (bool) {
        return MerkleProof.verify(proof, root, leaf);
    }

    struct PoolRebalanceLeaf {
        // This is used to know which chain to send cross-chain transactions to (and which SpokePool to send to).
        uint256 chainId;
        // Total LP fee amount per token in this bundle, encompassing all associated bundled relays.
        uint256[] bundleLpFees;
        // Represents the amount to push to or pull from the SpokePool. If +, the pool pays the SpokePool. If negative
        // the SpokePool pays the HubPool. There can be arbitrarily complex rebalancing rules defined offchain. This
        // number is only nonzero when the rules indicate that a rebalancing action should occur. When a rebalance does
        // occur, runningBalances must be set to zero for this token and netSendAmounts should be set to the previous
        // runningBalances + relays - deposits in this bundle. If non-zero then it must be set on the SpokePool's
        // RelayerRefundLeaf amountToReturn as -1 * this value to show if funds are being sent from or to the SpokePool.
        int256[] netSendAmounts;
        // This is only here to be emitted in an event to track a running unpaid balance between the L2 pool and the L1
        // pool. A positive number indicates that the HubPool owes the SpokePool funds. A negative number indicates that
        // the SpokePool owes the HubPool funds. See the comment above for the dynamics of this and netSendAmounts.
        int256[] runningBalances;
        // Used by data worker to mark which leaves should relay roots to SpokePools, and to otherwise organize leaves.
        // For example, each leaf should contain all the rebalance information for a single chain, but in the case where
        // the list of l1Tokens is very large such that they all can't fit into a single leaf that can be executed under
        // the block gas limit, then the data worker can use this groupIndex to organize them. Any leaves with
        // a groupIndex equal to 0 will relay roots to the SpokePool, so the data worker should ensure that only one
        // leaf for a specific chainId should have a groupIndex equal to 0.
        uint256 groupIndex;
        // Used as the index in the bitmap to track whether this leaf has been executed or not.
        uint8 leafId;
        // The bundleLpFees, netSendAmounts, and runningBalances are required to be the same length. They are parallel
        // arrays for the given chainId and should be ordered by the l1Tokens field. All whitelisted tokens with nonzero
        // relays on this chain in this bundle in the order of whitelisting.
        address[] l1Tokens;
    }

    function verifyPoolRebalance(
        bytes32 root,
        PoolRebalanceLeaf memory leaf,
        bytes32[] memory proof
    ) public pure returns (bool) {
        bytes32 node = keccak256(abi.encode(leaf)); 
        return MerkleProof.verify(proof, root, node);
    }
    
}