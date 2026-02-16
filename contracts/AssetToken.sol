// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import "./Interfaces/IComplianceModule.sol";
import "./Interfaces/IAssetToken.sol";

contract AssetToken is IAssetToken, Initializable, ERC1155Upgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using Checkpoints for Checkpoints.Trace208;

    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @custom:storage-location erc7201:rwa.storage.AssetToken
    struct AssetTokenStorage {
        IComplianceModule compliance;
        mapping(uint256 trancheId => uint256 amount) totalSupply;
        mapping(uint256 trancheId => uint256 cap) maxSupply;
        mapping(address => mapping(uint256 => Checkpoints.Trace208)) _balanceCheckpoints;
    }

    // keccak256(abi.encode(uint256(keccak256("rwa.storage.AssetToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ASSET_TOKEN_STORAGE_LOCATION =
        0x5d72fdf5a78734521badd28ecf70f1a3b98c4e0888add66fe3c779d77c5cdb00;

    function _getAssetTokenStorage() private pure returns (AssetTokenStorage storage $) {
        assembly { $.slot := ASSET_TOKEN_STORAGE_LOCATION }
    }

    event Minted(address indexed to, uint256 trancheId, uint256 amount);
    event Burned(address indexed from, uint256 trancheId, uint256 amount);
    event MaxSupplySet(uint256 indexed trancheId, uint256 cap);
    event ForcedTransfer(address indexed from, address indexed to, uint256 trancheId, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory uri_,
        address admin,
        address complianceModule
    ) public initializer {
        __ERC1155_init(uri_);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ISSUER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        $.compliance = IComplianceModule(complianceModule);
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function balanceOf(address account, uint256 id)
        public
        view
        override(IAssetToken, ERC1155Upgradeable)
        returns (uint256)
    {
        return super.balanceOf(account, id);
    }

    // ── Public Getters for Namespaced Storage ────────────────────────────

    function compliance() external view returns (IComplianceModule) {
        return _getAssetTokenStorage().compliance;
    }

    function totalSupply(uint256 trancheId) external view override returns (uint256) {
        return _getAssetTokenStorage().totalSupply[trancheId];
    }

    function maxSupply(uint256 trancheId) external view override returns (uint256) {
        return _getAssetTokenStorage().maxSupply[trancheId];
    }

    // ── Supply Management ──────────────────────────────────────────────

    /// @notice Set the maximum mintable supply for a tranche. 0 = unlimited.
    function setMaxSupply(uint256 trancheId, uint256 cap)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        require(cap == 0 || cap >= $.totalSupply[trancheId], "Cap below current supply");
        $.maxSupply[trancheId] = cap;
        emit MaxSupplySet(trancheId, cap);
    }

    function mint(
        address to,
        uint256 trancheId,
        uint256 amount
    ) external override onlyRole(ISSUER_ROLE) {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        uint256 cap = $.maxSupply[trancheId];
        if (cap != 0) {
            require($.totalSupply[trancheId] + amount <= cap, "Exceeds max supply");
        }
        _mint(to, trancheId, amount, "");
        $.totalSupply[trancheId] += amount;
        emit Minted(to, trancheId, amount);
    }

    function burn(
        address from,
        uint256 trancheId,
        uint256 amount
    ) external override onlyRole(ISSUER_ROLE) {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        _burn(from, trancheId, amount);
        $.totalSupply[trancheId] -= amount;
        emit Burned(from, trancheId, amount);
    }

    // ── Emergency Controls ─────────────────────────────────────────────

    function pause() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Regulatory forced transfer — bypasses compliance and pause checks.
    ///         Use only for court orders, regulatory clawbacks, or custody recovery.
    function forceTransfer(
        address from,
        address to,
        uint256 trancheId,
        uint256 amount
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        // Bypass compliance: call ERC1155 _update directly without our hook logic.
        // We still need to update checkpoints manually.
        uint256[] memory ids = new uint256[](1);
        uint256[] memory values = new uint256[](1);
        ids[0] = trancheId;
        values[0] = amount;

        // Call parent _update directly — skips our compliance override.
        super._update(from, to, ids, values);

        // Update checkpoints for both parties.
        uint48 clock = uint48(block.number);
        if (from != address(0)) {
            $._balanceCheckpoints[from][trancheId].push(clock, uint208(balanceOf(from, trancheId)));
        }
        if (to != address(0)) {
            $._balanceCheckpoints[to][trancheId].push(clock, uint208(balanceOf(to, trancheId)));
        }

        emit ForcedTransfer(from, to, trancheId, amount);
    }

    // ── Snapshot Queries ───────────────────────────────────────────────

    /// @notice Returns the token balance of `account` for tranche `id` at a specific block number.
    ///         Used by CorporateActionsModule to compute dividend payouts at the record-date snapshot.
    function balanceOfAt(address account, uint256 id, uint48 blockNumber)
        public
        view
        override
        returns (uint256)
    {
        return _getAssetTokenStorage()._balanceCheckpoints[account][id].upperLookupRecent(blockNumber);
    }

    // ── Transfer Hook ──────────────────────────────────────────────────

    /// @dev Transfer hook override. Called by all transfer/mint/burn operations.
    ///      Enforces:
    ///        - Global pause (whenNotPaused modifier)
    ///        - Compliance for all movements TO a real address (mints included).
    ///          canTransfer skips sender checks when from == address(0).
    ///          Burns (to == address(0)) are issuer-role-gated so compliance is not rechecked.
    ///      After state changes, snapshots each affected balance for later dividend lookups.
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override whenNotPaused {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        // Validate compliance for non-burn movements (covers transfers and mints).
        if (to != address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                require(
                    $.compliance.canTransfer(from, to, ids[i]),
                    "Compliance: transfer blocked"
                );
            }
        }

        super._update(from, to, ids, values);

        // Checkpoint new balances for snapshot-based dividend queries.
        uint48 clock = uint48(block.number);
        for (uint256 i = 0; i < ids.length; i++) {
            if (from != address(0)) {
                $._balanceCheckpoints[from][ids[i]].push(clock, uint208(balanceOf(from, ids[i])));
            }
            if (to != address(0)) {
                $._balanceCheckpoints[to][ids[i]].push(clock, uint208(balanceOf(to, ids[i])));
            }
        }
    }
}
