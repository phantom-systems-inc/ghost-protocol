// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IGhostERC20
/// @notice Interface for privacy-enabled ERC20 tokens on Ghost Protocol
interface IGhostERC20 is IERC20 {
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the gateway address (for cross-chain bridging)
    function gateway() external view returns (address);

    /// @notice Get the counterpart token address on other chain
    function counterpart() external view returns (address);

    /// @notice Get the GhostVault address
    function vault() external view returns (address);

    /// @notice Get the token ID hash used in privacy proofs
    function tokenIdHash() external view returns (bytes32);

    /// @notice Check if this token is ghost-enabled
    function isGhostEnabled() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                          GATEWAY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint tokens (only callable by gateway)
    function mint(address to, uint256 amount) external;

    /// @notice Burn tokens (only callable by gateway)
    function burn(address from, uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                          VAULT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Burn tokens for vanish operation (only callable by vault)
    function vaultTransferFrom(address from, uint256 amount) external;

    /// @notice Mint tokens for summon operation (only callable by vault)
    function vaultMint(address to, uint256 amount) external;
}
