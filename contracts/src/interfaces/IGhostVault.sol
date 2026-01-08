// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IGhostVault
/// @notice Interface for the Ghost Protocol privacy pool vault
/// @dev Main orchestrator for vanish/summon operations with ZK proof verification
interface IGhostVault {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Proof data for summon (Groth16)
    struct Proof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
    }

    /// @notice Public inputs for summon proof
    struct SummonInputs {
        bytes32 root;
        bytes32 nullifier;
        uint256 amount;
        address recipient;
        bytes32 changeCommitment;
        bytes32 tokenId;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when tokens vanish into the privacy pool
    event Vanish(
        address indexed token,
        address indexed sender,
        uint256 amount,
        bytes32 indexed commitment,
        uint256 leafIndex
    );

    /// @notice Emitted when tokens are summoned from the privacy pool
    event Summon(
        address indexed token,
        address indexed recipient,
        uint256 amount,
        bytes32 indexed nullifier
    );

    /// @notice Emitted when a change commitment is recorded
    event ChangeCommitment(bytes32 indexed commitment, uint256 leafIndex);

    /// @notice Emitted when native GHOST vanishes into the privacy pool
    event VanishNative(
        address indexed sender,
        uint256 amount,
        bytes32 indexed commitment,
        uint256 leafIndex
    );

    /// @notice Emitted when native GHOST is summoned from the privacy pool
    event SummonNative(
        address indexed recipient,
        uint256 amount,
        bytes32 indexed nullifier
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidToken();
    error InvalidAmount();
    error InvalidProof();
    error InvalidRoot();
    error NullifierAlreadySpent();
    error InvalidRecipient();
    error TransferFailed();
    error Paused();
    error InsufficientBalance();
    error InvalidTokenId();

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function commitmentTree() external view returns (address);
    function nullifierRegistry() external view returns (address);
    function summonVerifier() external view returns (address);
    function deployGuard() external view returns (address);
    function paused() external view returns (bool);
    function totalVanished(address token) external view returns (uint256);
    function totalNativeVanished() external view returns (uint256);
    function nativeTokenId() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                          VANISH FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Vanish tokens into the privacy pool
    /// @param token The token to vanish
    /// @param amount The amount to vanish
    /// @param commitment The pre-computed commitment hash
    function vanish(
        address token,
        uint256 amount,
        bytes32 commitment
    ) external returns (uint256 leafIndex);

    /// @notice Vanish native GHOST into the privacy pool
    /// @param commitment The pre-computed commitment hash
    function vanishNative(bytes32 commitment) external payable returns (uint256 leafIndex);

    /*//////////////////////////////////////////////////////////////
                          SUMMON FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Summon tokens from the privacy pool
    /// @param token The token to summon
    /// @param proof The ZK proof
    /// @param inputs The public inputs for verification
    function summon(
        address token,
        Proof calldata proof,
        SummonInputs calldata inputs
    ) external;

    /// @notice Summon native GHOST from the privacy pool
    /// @param proof The ZK proof
    /// @param inputs The public inputs for verification
    function summonNative(
        Proof calldata proof,
        SummonInputs calldata inputs
    ) external;

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external;
    function unpause() external;
}
