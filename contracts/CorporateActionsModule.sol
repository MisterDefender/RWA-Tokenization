// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/IAssetToken.sol";
import "./Interfaces/ICorporateActions.sol";

contract CorporateActionsModule is ICorporateActions, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @dev A dividend declaration for a specific tranche.
    ///      snapshotBlock is recorded at declaration time — claims use this to look up
    ///      each investor's balance AT that block, not at the time of claiming.
    struct DividendRound {
        uint256 amountPerToken; // how much each token earns (e.g., $5 in USDC per token as dividend)
        uint48 snapshotBlock;   // the block number when we recorded who holds what
    }

    /// @custom:storage-location erc7201:rwa.storage.CorporateActionsModule
    struct CorporateActionsStorage {
        IAssetToken token;
        IERC20 paymentToken;
        mapping(uint256 trancheId => uint256 roundNumber) currentRound;
        mapping(uint256 => mapping(uint256 => DividendRound)) dividendRounds;
        mapping(uint256 => mapping(uint256 => mapping(address => bool))) claimed;
    }

    // keccak256(abi.encode(uint256(keccak256("rwa.storage.CorporateActionsModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CORPORATE_ACTIONS_STORAGE_LOCATION =
        0x748fd548cc33f2f14b7552e0e3095090263bf6d35ae64c9ea49f016797e6d600;

    function _getCorporateActionsStorage() private pure returns (CorporateActionsStorage storage $) {
        assembly { $.slot := CORPORATE_ACTIONS_STORAGE_LOCATION }
    }

    event DividendDeclared(
        uint256 indexed trancheId,
        uint256 indexed round,
        uint256 amountPerToken,
        uint48 snapshotBlock
    );
    event DividendClaimed(
        address indexed investor,
        uint256 indexed trancheId,
        uint256 indexed round,
        uint256 payout
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address tokenAddress, address paymentTokenAddress) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        CorporateActionsStorage storage $ = _getCorporateActionsStorage();
        $.token = IAssetToken(tokenAddress);
        $.paymentToken = IERC20(paymentTokenAddress);
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /// @notice Declare a dividend for a tranche. Each call creates a new round,
    ///         so multiple undistributed dividends can coexist without overwriting each other.
    ///         The caller must have transferred sufficient paymentToken to this contract beforehand.
    ///         The system records the current block as the snapshot — even if you sell tokens AFTER
    ///         this declaration, you still get the dividend because the system remembers your balance.
    function declareDividend(
        uint256 trancheId,
        uint256 amountPerToken
    ) external override onlyRole(ADMIN_ROLE) {
        require(amountPerToken > 0, "Amount must be > 0");
        CorporateActionsStorage storage $ = _getCorporateActionsStorage();
        uint256 round = ++$.currentRound[trancheId];
        $.dividendRounds[trancheId][round] = DividendRound({
            amountPerToken: amountPerToken,
            snapshotBlock: uint48(block.number)
        });
        emit DividendDeclared(trancheId, round, amountPerToken, uint48(block.number));
    }

    /// @notice Claim a dividend payout for a specific round.
    ///         Payout is based on the investor's balance AT the snapshot block, not current balance.
    function claimDividend(uint256 trancheId, uint256 round) external override nonReentrant {
        CorporateActionsStorage storage $ = _getCorporateActionsStorage();
        require(!$.claimed[trancheId][round][msg.sender], "Already claimed");

        DividendRound memory dr = $.dividendRounds[trancheId][round];
        require(dr.snapshotBlock != 0, "Round does not exist");

        // Use snapshot balance — prevents gaming by buying after declaration.
        uint256 balance = $.token.balanceOfAt(msg.sender, trancheId, dr.snapshotBlock);
        require(balance > 0, "No holdings at snapshot block");

        uint256 payout = balance * dr.amountPerToken;

        // State before external call (CEI pattern + nonReentrant guard).
        $.claimed[trancheId][round][msg.sender] = true;

        // Pay in stablecoin via ERC20 transfer.
        require($.paymentToken.transfer(msg.sender, payout), "Payment failed");

        emit DividendClaimed(msg.sender, trancheId, round, payout);
    }
}
