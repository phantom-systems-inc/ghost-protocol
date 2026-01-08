// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IOpenProofVerifier
/// @notice Interface for Groth16 proof verification in the open Ghost Protocol
/// @dev The open protocol uses a generic verifier that checks:
///      1. Commitment exists in the Merkle tree (root validation)
///      2. Nullifier is correctly derived from secrets
///      3. dataHash matches the claimed value
///
///      Public inputs:
///        - root: Merkle root the commitment is proven under
///        - nullifier: Derived nullifier hash
///        - dataHash: Application-specific data hash
///        - recipient: Recipient address (as uint256)
interface IOpenProofVerifier {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProofLength();
    error InvalidPublicInputsLength();
    error ProofVerificationFailed();
    error InvalidInputValue();

    /*//////////////////////////////////////////////////////////////
                          VERIFICATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verify a Groth16 proof for the open protocol
    /// @param proof The proof elements [A.x, A.y, B.x[0], B.x[1], B.y[0], B.y[1], C.x, C.y]
    /// @param publicInputs The public inputs [root, nullifier, dataHash, recipient]
    /// @return isValid True if the proof is valid
    function verifyProof(
        uint256[8] calldata proof,
        uint256[4] calldata publicInputs
    ) external returns (bool isValid);

    /// @notice Verify proof with explicit public inputs
    /// @param proof The 8-element proof array
    /// @param root Merkle root
    /// @param nullifier Nullifier hash
    /// @param dataHash Application-specific data hash
    /// @param recipient Recipient address
    /// @return isValid True if proof is valid
    function verifyOpenProof(
        uint256[8] calldata proof,
        bytes32 root,
        bytes32 nullifier,
        bytes32 dataHash,
        address recipient
    ) external returns (bool isValid);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the number of public inputs for the circuit
    function NUM_PUBLIC_INPUTS() external view returns (uint256);
}
