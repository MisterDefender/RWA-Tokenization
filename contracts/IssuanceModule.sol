// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./Interfaces/IAssetToken.sol";
import "./Interfaces/IIssuanceModule.sol";

contract IssuanceModule is IIssuanceModule, Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    struct Subscription {
        uint256 trancheId;
        uint256 amount;
        bool approved;
    }

    /// @custom:storage-location erc7201:rwa.storage.IssuanceModule
    struct IssuanceModuleStorage {
        IAssetToken assetToken;
        mapping(address => mapping(uint256 => Subscription)) subscriptions;
    }

    // keccak256(abi.encode(uint256(keccak256("rwa.storage.IssuanceModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ISSUANCE_MODULE_STORAGE_LOCATION =
        0x70fe42cbc063eef14982553d357e24f81ff90bf403e6130b108e9ba7a4686500;

    function _getIssuanceModuleStorage() private pure returns (IssuanceModuleStorage storage $) {
        assembly { $.slot := ISSUANCE_MODULE_STORAGE_LOCATION }
    }

    event SubscriptionRequested(address indexed investor, uint256 trancheId, uint256 amount);
    event SubscriptionCancelled(address indexed investor, uint256 trancheId);
    event SubscriptionApproved(address indexed investor, uint256 trancheId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address token) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ISSUER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        IssuanceModuleStorage storage $ = _getIssuanceModuleStorage();
        $.assetToken = IAssetToken(token);
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /// @notice Investor requests tokens for a specific tranche. {pending} until issuer approval.
    ///         A new request can only be submitted if no unapproved request exists for that tranche.
    function requestSubscription(uint256 trancheId, uint256 amount) external override {
        require(amount > 0, "Amount must be > 0");
        IssuanceModuleStorage storage $ = _getIssuanceModuleStorage();
        Subscription storage existing = $.subscriptions[msg.sender][trancheId];
        require(
            existing.amount == 0 || existing.approved,
            "Pending request exists for this tranche"
        );
        $.subscriptions[msg.sender][trancheId] = Subscription(trancheId, amount, false);
        emit SubscriptionRequested(msg.sender, trancheId, amount);
    }

    /// @notice Investor cancels their own pending (unapproved) subscription.
    function cancelSubscription(uint256 trancheId) external override {
        IssuanceModuleStorage storage $ = _getIssuanceModuleStorage();
        Subscription storage sub = $.subscriptions[msg.sender][trancheId];
        require(sub.amount > 0 && !sub.approved, "No pending subscription");
        delete $.subscriptions[msg.sender][trancheId];
        emit SubscriptionCancelled(msg.sender, trancheId);
    }

    /// @notice Issuer approves a subscription and mints tokens to the investor.
    ///         Off-chain payment reconciliation must happen before calling this.
    function approveSubscription(address investor, uint256 trancheId)
        external
        override
        onlyRole(ISSUER_ROLE)
    {
        IssuanceModuleStorage storage $ = _getIssuanceModuleStorage();
        Subscription storage sub = $.subscriptions[investor][trancheId];
        require(sub.amount > 0, "No subscription found");
        require(!sub.approved, "Already approved");

        sub.approved = true;

        $.assetToken.mint(investor, sub.trancheId, sub.amount);

        emit SubscriptionApproved(investor, trancheId);
    }
}
