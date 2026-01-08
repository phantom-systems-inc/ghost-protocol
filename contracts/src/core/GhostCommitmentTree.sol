// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoseidonLib} from "../libraries/PoseidonLib.sol";

/// @title GhostCommitmentTree
/// @notice Off-chain incremental Merkle tree with on-chain root tracking for Ghost Protocol
/// @dev Implements "off-chain tree, on-chain roots" pattern for gas efficiency.
///      Full tree is maintained by off-chain indexers who listen to CommitmentAdded events.
///
///      On-chain tracking:
///        - Current root (updated by trusted operator)
///        - Root history (last N roots valid for redemption proofs)
///        - Leaf count for sequential ordering
///
///      Tree parameters:
///        - Depth: 20 levels (supports ~1M commitments)
///        - Hash: Poseidon T3 (2 inputs) for internal nodes
///        - Commitments: Pre-computed off-chain using Poseidon T6
contract GhostCommitmentTree is Ownable {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum tree depth (2^20 = ~1M leaves)
    uint256 public constant TREE_DEPTH = 20;

    /// @notice Maximum number of leaves supported
    uint256 public constant MAX_LEAVES = 1 << TREE_DEPTH; // 2^20 = 1,048,576

    /// @notice Number of historical roots to keep valid
    uint256 public constant ROOT_HISTORY_SIZE = 100;

    /// @notice Maximum staleness allowed for root updates
    uint256 public constant MAX_ROOT_STALENESS = 1000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The authorized contract that can record commitments (GhostVault)
    address public vault;

    /// @notice The authorized operator that can update roots
    address public rootOperator;

    /// @notice Current number of leaves in the tree
    uint256 public leafCount;

    /// @notice Current Merkle root
    bytes32 public currentRoot;

    /// @notice Index of the current root in the history ring buffer
    uint256 public currentRootIndex;

    /// @notice Ring buffer of historical roots
    bytes32[ROOT_HISTORY_SIZE] public rootHistory;

    /// @notice Mapping to check if a root is known (O(1) lookup)
    mapping(bytes32 => bool) public knownRoots;

    /// @notice Zero hashes for each level
    bytes32[TREE_DEPTH + 1] public zeroHashes;

    /// @notice Mapping to track recorded commitments (prevents duplicates)
    mapping(bytes32 => bool) public recordedCommitments;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new commitment is added
    event CommitmentAdded(bytes32 indexed commitment, uint256 indexed leafIndex, uint256 timestamp);

    /// @notice Emitted when the root is updated
    event RootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot, uint256 leafCount);

    /// @notice Emitted when root operator is changed
    event RootOperatorChanged(address indexed oldOperator, address indexed newOperator);

    /// @notice Emitted when vault is set
    event VaultSet(address indexed vault);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyVault();
    error OnlyOperator();
    error TreeFull();
    error InvalidRoot();
    error CommitmentAlreadyRecorded();
    error InvalidCommitment();
    error VaultAlreadySet();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the commitment tree
    /// @param initialOwner The initial owner (can set vault and operator)
    constructor(address initialOwner) Ownable(initialOwner) {
        rootOperator = initialOwner;

        // Initialize zero hashes using Poseidon
        _initializeZeroHashes();

        // Set initial root to empty tree root
        currentRoot = zeroHashes[TREE_DEPTH];
        rootHistory[0] = currentRoot;
        knownRoots[currentRoot] = true;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the vault address (one-time setup)
    /// @param _vault The GhostVault address
    function setVault(address _vault) external onlyOwner {
        if (vault != address(0)) revert VaultAlreadySet();
        require(_vault != address(0), "Invalid vault");
        vault = _vault;
        emit VaultSet(_vault);
    }

    /// @notice Initialize zero hashes for the empty tree
    function _initializeZeroHashes() internal {
        // Level 0: empty leaf is 0
        zeroHashes[0] = bytes32(0);

        // Each subsequent level: hash(zeroHash[i-1], zeroHash[i-1])
        for (uint256 i = 1; i <= TREE_DEPTH; i++) {
            zeroHashes[i] = PoseidonLib.hash2(zeroHashes[i - 1], zeroHashes[i - 1]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          COMMITMENT RECORDING
    //////////////////////////////////////////////////////////////*/

    /// @notice Record a new commitment (called by GhostVault)
    /// @param commitment The pre-computed commitment hash
    /// @return leafIndex The index of this commitment in the tree
    function recordCommitment(bytes32 commitment) external returns (uint256 leafIndex) {
        if (msg.sender != vault) revert OnlyVault();
        if (leafCount >= MAX_LEAVES) revert TreeFull();
        if (commitment == bytes32(0)) revert InvalidCommitment();
        if (!PoseidonLib.isValidCommitment(commitment)) revert InvalidCommitment();
        if (recordedCommitments[commitment]) revert CommitmentAlreadyRecorded();

        // Mark commitment as recorded (CEI pattern)
        recordedCommitments[commitment] = true;

        leafIndex = leafCount;
        unchecked {
            leafCount++;
        }

        emit CommitmentAdded(commitment, leafIndex, block.timestamp);

        return leafIndex;
    }

    /*//////////////////////////////////////////////////////////////
                            ROOT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Update the Merkle root (called by operator)
    /// @param newRoot The new Merkle root
    /// @param expectedLeafCount The leaf count the root was computed for
    function updateRoot(bytes32 newRoot, uint256 expectedLeafCount) external {
        if (msg.sender != rootOperator) revert OnlyOperator();
        if (expectedLeafCount > leafCount) revert InvalidRoot();
        if (leafCount - expectedLeafCount > MAX_ROOT_STALENESS) revert InvalidRoot();
        if (newRoot == bytes32(0)) revert InvalidRoot();

        bytes32 oldRoot = currentRoot;

        // HIGH-8 fix: Calculate next position and save the value that will be overwritten
        uint256 nextIndex = (currentRootIndex + 1) % ROOT_HISTORY_SIZE;
        bytes32 overwrittenRoot = rootHistory[nextIndex];

        // Update root history ring buffer
        currentRootIndex = nextIndex;
        rootHistory[currentRootIndex] = newRoot;
        knownRoots[newRoot] = true;

        // Remove overwritten root from known roots if it's not duplicated elsewhere
        if (overwrittenRoot != bytes32(0) && overwrittenRoot != newRoot) {
            bool stillInHistory = false;
            for (uint256 i = 0; i < ROOT_HISTORY_SIZE; i++) {
                if (i != currentRootIndex && rootHistory[i] == overwrittenRoot) {
                    stillInHistory = true;
                    break;
                }
            }
            if (!stillInHistory) {
                knownRoots[overwrittenRoot] = false;
            }
        }

        currentRoot = newRoot;

        emit RootUpdated(oldRoot, newRoot, expectedLeafCount);
    }

    /// @notice Check if a root is known (valid for proof verification)
    function isKnownRoot(bytes32 root) external view returns (bool) {
        return knownRoots[root];
    }

    /// @notice Get the root at a specific history index
    function getRootAtIndex(uint256 index) external view returns (bytes32) {
        require(index < ROOT_HISTORY_SIZE, "Index out of bounds");
        return rootHistory[index];
    }

    /// @notice Get all valid roots
    function getAllRoots() external view returns (bytes32[ROOT_HISTORY_SIZE] memory) {
        return rootHistory;
    }

    /*//////////////////////////////////////////////////////////////
                              ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Change the root operator
    function setRootOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "Invalid operator");
        address oldOperator = rootOperator;
        rootOperator = newOperator;
        emit RootOperatorChanged(oldOperator, newOperator);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the zero hash at a specific level
    function getZeroHash(uint256 level) external view returns (bytes32) {
        require(level <= TREE_DEPTH, "Level out of bounds");
        return zeroHashes[level];
    }

    /// @notice Get tree statistics
    function getTreeStats()
        external
        view
        returns (uint256 depth, uint256 leaves, uint256 maxLeaves, bytes32 root)
    {
        return (TREE_DEPTH, leafCount, MAX_LEAVES, currentRoot);
    }

    /// @notice Check if a commitment has been recorded
    function isCommitmentRecorded(bytes32 commitment) external view returns (bool) {
        return recordedCommitments[commitment];
    }
}
