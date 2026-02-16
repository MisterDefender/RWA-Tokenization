// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IComplianceModule {
    enum InvestorType {
        NONE,
        RETAIL,      // regular person
        ACCREDITED,  // wealthy individual (net worth > $1M typically)
        INSTITUTIONAL // banks, funds, etc.
    }

    /// @notice Returns true if the transfer is compliant.
    ///         When from == address(0) (mint), only the receiver is validated.
    function canTransfer(
        address from,
        address to,
        uint256 trancheId
    ) external view returns (bool);

    /// @notice Set or update investor compliance data (allowlist + jurisdiction + type).
    ///         Preserves frozen status — use freeze() to change it.
    function setInvestor(
        address investor,
        bool allowlisted,
        uint8 jurisdiction,
        InvestorType investorType
    ) external;

    /// @notice Freeze or unfreeze an investor address.
    function freeze(address investor, bool status) external;

    /// @notice Set per-tranche compliance requirements.
    function setTrancheRequirements(
        uint256 trancheId,
        uint8 jurisdiction,
        InvestorType investorType
    ) external;

    /// @notice Read investor compliance data.
    function getInvestor(address investor)
        external
        view
        returns (
            bool allowlisted,
            bool frozen,
            uint8 jurisdiction,
            InvestorType investorType
        );
}
