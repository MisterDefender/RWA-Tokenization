// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICorporateActions {
    /// @notice Declare a new dividend round for a tranche.
    ///         Creates a new epoch — previous unclaimed rounds are not overwritten.
    ///         Snapshot is taken at the block of this call.
    function declareDividend(
        uint256 trancheId,
        uint256 amountPerToken
    ) external;

    /// @notice Claim dividend payout for a specific round.
    ///         Payout is based on the investor's balance at the snapshot block, not current balance.
    function claimDividend(uint256 trancheId, uint256 round) external;
}