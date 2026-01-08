// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IGhostRedemptionVerifier
/// @notice Interface for Groth16 proof verification
interface IGhostRedemptionVerifier {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProofVerified(bytes32 indexed nullifier, address indexed recipient, uint256 amount);
    event VerificationFailed(bytes32 indexed nullifier, string reason);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProofLength();
    error InvalidPublicInputsLength();
    error ProofVerificationFailed();
    error InvalidInputValue();
    error PairingFailed();

    /*//////////////////////////////////////////////////////////////
                          VERIFICATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verify a Groth16 proof for redemption
    /// @param proof The proof elements [A.x, A.y, B.x[0], B.x[1], B.y[0], B.y[1], C.x, C.y]
    /// @param publicInputs The public inputs [root, nullifier, amount, recipient, change_commitment, token_id]
    /// @return isValid True if the proof is valid
    function verifyProof(
        uint256[8] calldata proof,
        uint256[6] calldata publicInputs
    ) external view returns (bool isValid);

    /// @notice Verify proof with explicit public inputs
    /// @param proof The 8-element proof array
    /// @param root Merkle root
    /// @param nullifier Nullifier hash
    /// @param amount Withdrawal amount
    /// @param recipient Recipient address
    /// @param changeCommitment Change commitment (0 for full withdrawal)
    /// @param tokenId Token identifier
    /// @return isValid True if proof is valid
    function verifyRedemptionProof(
        uint256[8] calldata proof,
        bytes32 root,
        bytes32 nullifier,
        uint256 amount,
        address recipient,
        bytes32 changeCommitment,
        bytes32 tokenId
    ) external view returns (bool isValid);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the number of public inputs for the circuit
    function NUM_PUBLIC_INPUTS() external view returns (uint256);

    /// @notice Get IC point at index
    /// @param index The index (0 to NUM_PUBLIC_INPUTS)
    /// @return x X coordinate
    /// @return y Y coordinate
    function getIC(uint256 index) external view returns (uint256 x, uint256 y);
}
