// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title GhostNullifierRegistry
/// @notice Tracks spent nullifiers to prevent double-spending in Ghost Protocol
/// @dev Simple mapping-based registry with O(1) lookup and insertion.
///      Only GhostVault can record nullifiers after successful proof verification.
///
///      Security invariant: Once a nullifier is recorded, it cannot be unrecorded.
contract GhostNullifierRegistry is Ownable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The authorized contract that can record nullifiers (GhostVault)
    address public vault;

    /// @notice Mapping of nullifier hash to spent status
    mapping(bytes32 => bool) public nullifiers;

    /// @notice Total count of recorded nullifiers
    uint256 public nullifierCount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a nullifier is recorded
    event NullifierRecorded(bytes32 indexed nullifier, uint256 timestamp);

    /// @notice Emitted when vault is set
    event VaultSet(address indexed vault);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyVault();
    error NullifierAlreadySpent();
    error InvalidNullifier();
    error VaultAlreadySet();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the nullifier registry
    /// @param initialOwner The initial owner (can set vault)
    constructor(address initialOwner) Ownable(initialOwner) {
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

    /*//////////////////////////////////////////////////////////////
                          NULLIFIER RECORDING
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if a nullifier has been spent
    function isSpent(bytes32 nullifier) external view returns (bool) {
        return nullifiers[nullifier];
    }

    /// @notice Record a nullifier as spent (called by GhostVault)
    function recordNullifier(bytes32 nullifier) external {
        if (msg.sender != vault) revert OnlyVault();
        if (nullifier == bytes32(0)) revert InvalidNullifier();
        if (nullifiers[nullifier]) revert NullifierAlreadySpent();

        nullifiers[nullifier] = true;
        unchecked {
            nullifierCount++;
        }

        emit NullifierRecorded(nullifier, block.timestamp);
    }

    /// @notice Check and record a nullifier atomically
    /// @return wasSpent Always returns false (reverts if already spent)
    function checkAndRecord(bytes32 nullifier) external returns (bool wasSpent) {
        if (msg.sender != vault) revert OnlyVault();
        if (nullifier == bytes32(0)) revert InvalidNullifier();

        wasSpent = nullifiers[nullifier];
        if (wasSpent) revert NullifierAlreadySpent();

        nullifiers[nullifier] = true;
        unchecked {
            nullifierCount++;
        }

        emit NullifierRecorded(nullifier, block.timestamp);
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Batch check multiple nullifiers
    function batchIsSpent(bytes32[] calldata nullifierList)
        external
        view
        returns (bool[] memory spentStatus)
    {
        uint256 length = nullifierList.length;
        spentStatus = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            spentStatus[i] = nullifiers[nullifierList[i]];
        }

        return spentStatus;
    }

    /// @notice Get registry statistics
    function getStats() external view returns (uint256 count, address vaultAddress) {
        return (nullifierCount, vault);
    }
}
