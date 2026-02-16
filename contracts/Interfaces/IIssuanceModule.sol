// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIssuanceModule {
    /// @notice Investor requests tokens for a specific tranche.
    ///         Only one unapproved request per tranche is allowed at a time.
    function requestSubscription(
        uint256 trancheId,
        uint256 amount
    ) external;

    /// @notice Investor cancels their own pending (unapproved) subscription.
    function cancelSubscription(uint256 trancheId) external;

    /// @notice Issuer approves a pending subscription, minting tokens to the investor.
    ///         Off-chain KYC and payment reconciliation must be complete before calling this.
    function approveSubscription(
        address investor,
        uint256 trancheId
    ) external;
}
