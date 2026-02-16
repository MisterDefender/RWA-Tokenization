// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IComplianceModule} from "./Interfaces/IComplianceModule.sol";

contract ComplianceModule is IComplianceModule, Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant COMPLIANCE_ADMIN_ROLE = keccak256("COMPLIANCE_ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    struct InvestorData {
        bool allowlisted; // passed KYC (identity verification)?
        bool frozen;      // account frozen?
        uint8 jurisdiction; // ISO numeric code (no PII) which country
        InvestorType investorType; // inherited from IComplianceModule
    }

    /// @custom:storage-location erc7201:rwa.storage.ComplianceModule
    struct ComplianceModuleStorage {
        mapping(address => InvestorData) investors;
        mapping(uint256 => uint8) requiredJurisdiction;
        mapping(uint256 => InvestorType) requiredInvestorType;
    }

    // keccak256(abi.encode(uint256(keccak256("rwa.storage.ComplianceModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COMPLIANCE_MODULE_STORAGE_LOCATION =
        0xa9488e6fc6c8f1790456e8e878661666cfd45c2c19096cca12eda4fb202fea00;

    function _getComplianceModuleStorage() private pure returns (ComplianceModuleStorage storage $) {
        assembly { $.slot := COMPLIANCE_MODULE_STORAGE_LOCATION }
    }

    event InvestorUpdated(address indexed investor);
    event InvestorFrozen(address indexed investor, bool frozen);
    event TrancheRequirementUpdated(uint256 indexed trancheId, uint8 jurisdiction, InvestorType investorType);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COMPLIANCE_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /// @notice Set or update investor compliance data.
    ///         Preserves the existing frozen status — use freeze() to change it.
    function setInvestor(
        address investor,
        bool allowlisted,
        uint8 jurisdiction,
        InvestorType investorType
    ) external override onlyRole(COMPLIANCE_ADMIN_ROLE) {
        ComplianceModuleStorage storage $ = _getComplianceModuleStorage();
        bool currentFrozen = $.investors[investor].frozen; // preserve frozen state
        $.investors[investor] = InvestorData(
            allowlisted,
            currentFrozen,
            jurisdiction,
            investorType
        );
        emit InvestorUpdated(investor);
    }

    function freeze(address investor, bool status)
        external
        override
        onlyRole(COMPLIANCE_ADMIN_ROLE)
    {
        ComplianceModuleStorage storage $ = _getComplianceModuleStorage();
        $.investors[investor].frozen = status;
        emit InvestorFrozen(investor, status);
    }

    function setTrancheRequirements(
        uint256 trancheId,
        uint8 jurisdiction,
        InvestorType investorType
    ) external override onlyRole(COMPLIANCE_ADMIN_ROLE) {
        ComplianceModuleStorage storage $ = _getComplianceModuleStorage();
        $.requiredJurisdiction[trancheId] = jurisdiction;
        $.requiredInvestorType[trancheId] = investorType;
        emit TrancheRequirementUpdated(trancheId, jurisdiction, investorType);
    }

    /// @notice Read investor compliance data. Allows backend, frontend, and other contracts
    ///         to query investor status without exposing the mapping directly.
    function getInvestor(address investor)
        external
        view
        override
        returns (
            bool allowlisted,
            bool frozen,
            uint8 jurisdiction,
            InvestorType investorType
        )
    {
        ComplianceModuleStorage storage $ = _getComplianceModuleStorage();
        InvestorData memory data = $.investors[investor];
        return (data.allowlisted, data.frozen, data.jurisdiction, data.investorType);
    }

    function canTransfer(
        address from,
        address to,
        uint256 trancheId
    ) external view override returns (bool) {
        ComplianceModuleStorage storage $ = _getComplianceModuleStorage();
        InvestorData memory receiver = $.investors[to];

        // Sender checks only for non-mint transfers (from != address(0))
        if (from != address(0)) {
            InvestorData memory sender = $.investors[from];
            if (!sender.allowlisted || sender.frozen) return false;
        }

        if (!receiver.allowlisted || receiver.frozen) return false;

        if (
            $.requiredJurisdiction[trancheId] != 0 &&
            receiver.jurisdiction != $.requiredJurisdiction[trancheId]
        ) return false;

        if (
            $.requiredInvestorType[trancheId] != InvestorType.NONE &&
            receiver.investorType != $.requiredInvestorType[trancheId]
        ) return false;

        return true;
    }
}
