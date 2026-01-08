// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IGhostProtocol
/// @notice Core interface for the permissionless Ghost Protocol commitment system
/// @dev This interface defines the commitment lifecycle:
///      1. commit() - Add a commitment to the tree
///      2. verifyAndNullify() - Verify proof and record nullifier
///      3. isNullifierUsed() - Check replay prevention
///
///      The protocol is agnostic to what commitments represent.
///      Applications define meaning and implement IGhostApplication.
interface IGhostProtocol {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Groth16 proof data
    struct Proof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a commitment is added to the tree
    /// @param commitment The Poseidon hash commitment
    /// @param leafIndex The index in the Merkle tree
    /// @param timestamp Block timestamp when added
    event Committed(bytes32 indexed commitment, uint256 indexed leafIndex, uint256 timestamp);

    /// @notice Emitted when a commitment is revealed (nullifier recorded)
    /// @param nullifier The nullifier hash
    /// @param dataHash The application-specific data hash
    /// @param recipient The revelation recipient
    event Revealed(bytes32 indexed nullifier, bytes32 indexed dataHash, address indexed recipient);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCommitment();
    error InvalidProof();
    error InvalidRoot();
    error NullifierAlreadyUsed();
    error TreeFull();
    error InvalidRecipient();
    error CommitmentAlreadyExists();
    error SpamPrevention();

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Add a commitment to the tree
    /// @param commitment The Poseidon hash to add
    /// @return leafIndex The index in the Merkle tree
    /// @dev Commitments are computed off-chain:
    ///      commitment = Poseidon(secret, nullifierSecret, dataHash, blinding)
    function commit(bytes32 commitment) external payable returns (uint256 leafIndex);

    /// @notice Verify a proof and record the nullifier
    /// @param proof Groth16 proof data
    /// @param nullifier The nullifier to record
    /// @param root The Merkle root used in proof generation
    /// @param dataHash Application-specific data hash from proof
    /// @param recipient The recipient address
    /// @return valid Whether proof verified and nullifier was unused
    function verifyAndNullify(
        Proof calldata proof,
        bytes32 nullifier,
        bytes32 root,
        bytes32 dataHash,
        address recipient
    ) external returns (bool valid);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if a nullifier has been used
    /// @param nullifier The nullifier to check
    /// @return used True if nullifier was already recorded
    function isNullifierUsed(bytes32 nullifier) external view returns (bool used);

    /// @notice Check if a root is valid (in history)
    /// @param root The Merkle root to verify
    /// @return valid True if root is in the valid history
    function isValidRoot(bytes32 root) external view returns (bool valid);

    /// @notice Get the current Merkle root
    /// @return root The current root hash
    function getRoot() external view returns (bytes32 root);

    /// @notice Get the current leaf count
    /// @return count Number of commitments in the tree
    function getLeafCount() external view returns (uint256 count);

    /// @notice Get protocol addresses
    /// @return tree The commitment tree address
    /// @return registry The nullifier registry address
    /// @return verifier The ZK proof verifier address
    function getAddresses() external view returns (address tree, address registry, address verifier);
}
