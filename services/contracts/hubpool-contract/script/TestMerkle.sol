// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { MerkleVerifier } from "../src/MerkleVerifier.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MerkleRebalanceTest is Test {
    MerkleVerifier verifier;

    function setUp() public {
        verifier = new MerkleVerifier();
    }

    struct PoolRebalanceLeaf {
        uint256 chainId;
        uint256[] bundleLpFees;
        int256[] netSendAmounts;
        int256[] runningBalances;
        uint256 groupIndex;
        uint8 leafId;
        address[] l1Tokens;
    }

    struct RelayerRefundLeaf {
        uint256 amountToReturn;
        uint256 chainId;
        uint256[] refundAmounts;
        uint32 leafId;
        address l2TokenAddress;
        address[] refundAddresses;
    }

    function hashLeaf(PoolRebalanceLeaf memory leaf) internal pure returns (bytes32) {
        return keccak256(abi.encode(leaf));
    }
    function hashRelayerLeaf(RelayerRefundLeaf memory leaf) internal pure returns (bytes32) {
        return keccak256(abi.encode(leaf));
    }

    function testVerifyPoolRebalance() public {
        PoolRebalanceLeaf memory leaf0 = PoolRebalanceLeaf({
            chainId: 11155111,
            bundleLpFees: new uint256[](0),
            netSendAmounts: new int256[](0) ,
            runningBalances: new int256[](0),
            groupIndex: 0,
            leafId: 0,
            l1Tokens: new address[](0) 
        });

        PoolRebalanceLeaf memory leaf1 = PoolRebalanceLeaf({
            chainId: 421614,
            bundleLpFees: new uint256[](0) ,
            netSendAmounts: new int256[](0) ,
            runningBalances: new int256[](0) ,
            groupIndex: 0,
            leafId: 1,
            l1Tokens: new address[](0) 
        });

        bytes32 hash0 = hashLeaf(leaf0);
        bytes32 hash1 = hashLeaf(leaf1);

        (bytes32 left, bytes32 right) = hash0 < hash1 ? (hash0, hash1) : (hash1, hash0);
        bytes32 root = keccak256(abi.encodePacked(left, right));
        emit log_named_bytes32("root", root);


        // Generate proof for leaf0
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = hash1;

        // Validate using MerkleVerifier contract
        bool isValid = verifier.verifyProof(root, proof, hash0);
        assertTrue(isValid, "Proof should be valid for leaf0");

        // Negative test: wrong leaf
        bytes32 fakeLeaf = keccak256("wrong");
        bool invalid = verifier.verifyProof(root, proof, fakeLeaf);
        assertFalse(invalid, "Fake leaf should fail verification");

        emit log_named_bytes32("leaf0", hash0);
        emit log_named_bytes32("leaf1", hash1);
    }

    function testVerifyRelayerRefund() public {
        RelayerRefundLeaf memory leaf = RelayerRefundLeaf({
            amountToReturn: 19500,
            chainId: 11155111,
            refundAmounts: new uint256[](19500),
            leafId: 0,
            l2TokenAddress: address(0x6b73250CFF2DCE3426D41a45f6f7543C65786d96),
            refundAddresses: array1Addr(0xca0AAC84A57e239A2918E9537BCc3Ee29E24b6cd)
        });

        bytes32 leafHash = hashRelayerLeaf(leaf);
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = leafHash;

        // Build Merkle tree (only one leaf, so root = leaf)
        bytes32 root = leafHash;
        bytes32[] memory proof = new bytes32[](0); // No proof needed

        emit log_named_bytes32("relayerLeafHash", leafHash);
        emit log_named_bytes32("relayerRoot", root);

        // Should validate
        bool isValid = verifier.verifyProof(root, proof, leafHash);
        assertTrue(isValid, "RelayerRefund proof should be valid");
    }

    function array1Addr(address val) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = val;
    }



}
