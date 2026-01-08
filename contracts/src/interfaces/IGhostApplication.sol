// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IGhostApplication
/// @notice Interface for applications building on Ghost Protocol
/// @dev Applications implement this interface to define:
///      - What dataHash represents (tokens, credentials, access rights, etc.)
///      - What happens when users commit (lock tokens, record credentials)
///      - What happens when users reveal (transfer tokens, grant access)
///
///      The protocol calls these hooks during commit/reveal operations.
///      Applications are responsible for their own logic and security.
interface IGhostApplication {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user commits through this application
    event ApplicationCommit(address indexed user, bytes32 indexed dataHash, bytes data);

    /// @notice Emitted when a user reveals through this application
    event ApplicationReveal(address indexed recipient, bytes32 indexed dataHash, bytes data);

    /*//////////////////////////////////////////////////////////////
                            CALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Called when a user commits data through this application
    /// @param user The user creating the commitment
    /// @param dataHash The hash of application-specific data
    /// @param data Raw application data (for decoding)
    /// @dev This is called BEFORE the commitment is added to the tree.
    ///      Applications should lock/escrow assets here.
    ///      Revert to prevent the commitment from being recorded.
    function onCommit(address user, bytes32 dataHash, bytes calldata data) external;

    /// @notice Called when a user reveals data through this application
    /// @param recipient The recipient of the revelation
    /// @param dataHash The hash of revealed data (from ZK proof)
    /// @param data Raw application data (for decoding)
    /// @dev This is called AFTER proof verification and nullifier recording.
    ///      Applications should release/transfer assets here.
    ///      Revert to prevent the reveal from completing.
    function onReveal(address recipient, bytes32 dataHash, bytes calldata data) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Compute dataHash from raw application data
    /// @param data The raw application-specific data
    /// @return dataHash The Poseidon hash of the data
    /// @dev Used by clients to compute the dataHash for commitments.
    ///      Must be deterministic and match circuit expectations.
    function computeDataHash(bytes calldata data) external view returns (bytes32 dataHash);

    /// @notice Check if a commitment with this dataHash can be made
    /// @param user The user attempting to commit
    /// @param dataHash The data hash being committed
    /// @return canCommit True if the commitment is valid for this application
    /// @dev Used for pre-flight checks before commitment.
    ///      Does not guarantee onCommit will succeed.
    function canCommit(address user, bytes32 dataHash) external view returns (bool canCommit);

    /// @notice Get application metadata
    /// @return name Human-readable application name
    /// @return version Application version string
    function applicationInfo() external view returns (string memory name, string memory version);
}
