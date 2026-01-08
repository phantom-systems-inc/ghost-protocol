// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "poseidon-solidity/PoseidonT3.sol";

/// @title PoseidonLib
/// @notice Library for Poseidon hash operations on Avalanche L1
/// @dev ARCHITECTURE DECISION: Only PoseidonT3 (2 inputs) is used on-chain.
///
/// ## Gas Efficiency Design
///
/// Benchmark results (median, 5 runs):
/// - PoseidonT3 (2 inputs): 30,485 gas ✅
/// - PoseidonT6 (5 inputs): 179,086 gas ❌ (exceeded 80k threshold)
///
/// ## Commitment Generation: OFF-CHAIN ONLY
///
/// Commitments are generated client-side (webapp, mobile, NFC) using:
///   commitment = Poseidon5(secret, nullifierSecret, tokenId, amount, blinding)
///
/// The contract accepts pre-computed commitments as bytes32.
/// Client implementations MUST use identical Poseidon parameters to the ZK circuit.
///
/// ## On-Chain Poseidon Usage (T3 only)
///
/// 1. Merkle tree insertions: hash(left, right)
/// 2. Merkle proof verification: hash(sibling, current)
/// 3. Nullifier derivation: hash(hash(nullifierSecret, commitment), leafIndex)
/// 4. Token ID computation: hash(tokenAddress, 0)
///
library PoseidonLib {
    /// @dev BN254 scalar field order (same as alt_bn128)
    uint256 internal constant FIELD_SIZE =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @notice Hash two values using PoseidonT3 (2 inputs)
    /// @param left First input value
    /// @param right Second input value
    /// @return result The Poseidon hash
    function hash2(uint256 left, uint256 right) internal pure returns (uint256 result) {
        return PoseidonT3.hash([left, right]);
    }

    /// @notice Hash two bytes32 values using PoseidonT3
    /// @param left First input value
    /// @param right Second input value
    /// @return result The Poseidon hash as bytes32
    function hash2(bytes32 left, bytes32 right) internal pure returns (bytes32 result) {
        return bytes32(PoseidonT3.hash([uint256(left), uint256(right)]));
    }

    /// @notice Compute nullifier for Ghost Protocol
    /// @dev nullifier = hash(hash(nullifierSecret, commitment), leafIndex)
    /// @param nullifierSecret 254-bit nullifier derivation secret
    /// @param commitment The commitment being spent
    /// @param leafIndex Position in the Merkle tree
    /// @return nullifier The nullifier hash
    function computeNullifier(
        bytes32 nullifierSecret,
        bytes32 commitment,
        uint256 leafIndex
    ) internal pure returns (bytes32 nullifier) {
        // First hash nullifierSecret with commitment
        bytes32 intermediate = hash2(nullifierSecret, commitment);
        // Then hash with leafIndex
        return hash2(intermediate, bytes32(leafIndex));
    }

    /// @notice Compute token ID from token address
    /// @dev tokenId = hash(tokenAddress, 0)
    /// @param token The GhostERC20 token address
    /// @return tokenId The hashed token identifier
    function computeTokenId(address token) internal pure returns (bytes32 tokenId) {
        bytes32 tokenBytes = bytes32(uint256(uint160(token)));
        return hash2(tokenBytes, bytes32(0));
    }

    /// @notice Verify a value is within the BN254 scalar field
    /// @param value The value to check
    /// @return valid True if value < FIELD_SIZE
    function isValidFieldElement(uint256 value) internal pure returns (bool valid) {
        return value < FIELD_SIZE;
    }

    /// @notice Verify a bytes32 commitment is a valid field element
    /// @param commitment The commitment to validate
    /// @return valid True if commitment is a valid field element
    function isValidCommitment(bytes32 commitment) internal pure returns (bool valid) {
        return uint256(commitment) < FIELD_SIZE;
    }
}
