// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAssetToken {
    function mint(
        address to,
        uint256 trancheId,
        uint256 amount
    ) external;

    function burn(
        address from,
        uint256 trancheId,
        uint256 amount
    ) external;

    function pause() external;
    function unpause() external;

    function balanceOf(address account, uint256 id) external view returns (uint256);

    /// @notice Balance at a specific block — used by CorporateActionsModule for snapshot dividends.
    function balanceOfAt(address account, uint256 id, uint48 blockNumber) external view returns (uint256);

    function totalSupply(uint256 trancheId) external view returns (uint256);
    function maxSupply(uint256 trancheId) external view returns (uint256);

    /// @notice Set the maximum mintable supply for a tranche. 0 = unlimited.
    function setMaxSupply(uint256 trancheId, uint256 cap) external;

    /// @notice Regulatory forced transfer — bypasses compliance checks.
    ///         Restricted to DEFAULT_ADMIN_ROLE. Use only for court orders / regulatory clawbacks.
    function forceTransfer(
        address from,
        address to,
        uint256 trancheId,
        uint256 amount
    ) external;
}
