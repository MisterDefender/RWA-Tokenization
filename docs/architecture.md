# RWA Tokenization Platform – Architecture Document

## 1. Overview

This document describes the architecture of a **Real-World Asset (RWA) tokenization platform** designed to support compliant issuance, distribution, holding, and lifecycle management of tokenized assets on an EVM-compatible blockchain.

The design prioritizes:

* **On-chain enforceable compliance**
* **Modular smart contract architecture**
* **Operational realism** (custody, admin controls, observability)
* **Incremental deployability** by a small engineering team

The platform supports **multiple asset issuers**, **multiple investor classes**, and **tranche-based assets** using the ERC-1155 token standard.

---

## 2. Design Goals & Non-Goals

### Goals

* Strong compliance guarantees enforced **on-chain**
* Support for **tranches/classes** with differentiated rights
* Clear separation of concerns between contracts, backend, and frontend
* Upgrade-safe and governance-aware design
* Feasible implementation without exotic infrastructure

### Non-Goals

* Storing PII on-chain
* High-frequency trading or AMM integration
* Fully automated legal enforcement (off-chain legal processes assumed)

---

## 3. High-Level System Architecture

### Components

1. **Smart Contracts (EVM)**

   * Asset token contract (ERC-1155) — `AssetToken`
   * Compliance enforcement module — `ComplianceModule`
   * Issuance / primary market module — `IssuanceModule`
   * Corporate actions module — `CorporateActionsModule`

2. **Backend (Node.js)**

   * Investor onboarding & KYC coordination
   * Jurisdiction & investor-type management
   * Subscription approval workflows
   * Event ingestion and reconciliation
   * Admin & issuer APIs

3. **Frontend (Web App)**

   * Issuer dashboard
   * Investor dashboard
   * Wallet-based interactions only

4. **Custody Provider (Assumed)**

   * MPC or multisig wallets for issuers / treasury
   * External to platform trust boundary

---

### Trust Boundaries

| Layer           | Trust Assumption           |
| --------------- | -------------------------- |
| Smart Contracts | Trustless, source of truth |
| Backend         | Semi-trusted coordinator   |
| Frontend        | Untrusted                  |
| Custody         | Trusted but monitored      |
| Blockchain      | Assumed secure             |

**Compliance rules must never rely solely on the backend.**

---

## 4. Token Model & Standard Choice

### ERC-1155 with Tranches

Each real-world asset is represented by **multiple ERC-1155 token IDs**, where each token ID corresponds to a **tranche or class**.

Example:

| Token ID | Tranche | Rights                                |
| -------- | ------- | ------------------------------------- |
| 1        | Senior  | Priority coupon, restricted investors |
| 2        | Junior  | Higher yield, higher risk             |
| 3        | Equity  | Residual claim                        |

### Justification

* ERC-20 cannot express multiple classes cleanly
* ERC-721 is ill-suited for fractional ownership
* ERC-1155 enables:

  * Gas-efficient batch operations
  * Shared compliance logic
  * Clean tranche separation

---

## 5. Smart Contract Architecture

All contracts implement their corresponding interfaces defined in `/contracts/Interfaces/`. Each contract inherits its interface using Solidity's `is` keyword, ensuring compile-time verification of the contract-to-interface contract.

### Contract Responsibilities

#### 5.1 AssetToken (`AssetToken.sol`)

* ERC-1155 compliant token (OpenZeppelin v5), implements `IAssetToken`
* Holds balances and supply per tranche
* **Per-tranche supply cap** via `maxSupply` mapping — `setMaxSupply(trancheId, cap)` enforces a hard ceiling on minting (0 = unlimited)
* Delegates compliance checks to `ComplianceModule` via the OZ v5 `_update` hook
* Emits events for observability: `Minted`, `Burned`, `MaxSupplySet`, `ForcedTransfer`
* Supports pause / unpause (global transfer halt)
* **Forced transfer** capability: `forceTransfer(from, to, trancheId, amount)` — restricted to `DEFAULT_ADMIN_ROLE`, bypasses compliance and pause checks. Used for court orders, regulatory clawbacks, or custody recovery. Calls `super._update()` directly to skip the compliance hook.
* Stores per-address per-tranche balance checkpoints (`Checkpoints.Trace208`) for snapshot-based dividend accounting
* Exposes `balanceOfAt(account, trancheId, blockNumber)` for historical balance queries

#### 5.2 ComplianceModule (`ComplianceModule.sol`)

* Implements `IComplianceModule` — the `InvestorType` enum is defined in the interface and shared across all contracts
* Maintains allowlist status, freeze state, jurisdiction, and investor type per address
* `setInvestor()` **preserves existing frozen state** — updating jurisdiction or investor type will not accidentally unfreeze an investor. Use `freeze()` explicitly to change frozen status.
* `getInvestor()` view function — allows backend, frontend, and other contracts to query investor compliance data
* Enforces jurisdiction restrictions per tranche via `requiredJurisdiction[trancheId]`
* Enforces investor-type restrictions per tranche via `requiredInvestorType[trancheId]`
* `canTransfer(from, to, trancheId)` — when `from == address(0)` (mint), only the receiver is validated; sender checks are applied only for peer transfers
* Emits: `InvestorUpdated`, `InvestorFrozen`, `TrancheRequirementUpdated`

Compliance checks are executed **inside the `_update` token hook**, ensuring enforcement at the protocol level.

#### 5.3 IssuanceModule (`IssuanceModule.sol`)

* Implements `IIssuanceModule`
* Handles primary issuance flows
* Supports request → approval → mint pattern
* Per-tranche subscriptions: `mapping(investor => mapping(trancheId => Subscription))` — an investor may have concurrent pending requests across different tranches
* **Subscription cancellation**: investors can cancel their own pending (unapproved) subscriptions via `cancelSubscription(trancheId)`
* Input validation: `requestSubscription` requires `amount > 0`
* Prevents unauthorized minting — only `ISSUER_ROLE` can approve
* Integrates with off-chain payment reconciliation
* Emits: `SubscriptionRequested`, `SubscriptionCancelled`, `SubscriptionApproved`

#### 5.4 CorporateActionsModule (`CorporateActionsModule.sol`)

* Implements `ICorporateActions`
* Inherits OpenZeppelin `ReentrancyGuard` — `claimDividend` uses both the CEI (Checks-Effects-Interactions) pattern and the `nonReentrant` modifier for defense-in-depth
* Dividend / coupon distributions paid in **stablecoin** (e.g. USDC via `IERC20`)
* Epoch/round-based: each `declareDividend` call creates a new round — multiple undistributed dividends can coexist per tranche without overwriting each other
* Input validation: `declareDividend` requires `amountPerToken > 0`
* Snapshot-based accounting: `snapshotBlock` is recorded at declaration time; `claimDividend` calls `token.balanceOfAt(investor, trancheId, snapshotBlock)` to read the balance at the record date, not at claim time
* Claim-based pull model: investors call `claimDividend(trancheId, round)` individually
* Emits: `DividendDeclared`, `DividendClaimed`

---

### Compliance Enforcement Pattern

All token movements flow through:

```
ERC-1155 transfer / mint / burn
  → AssetToken._update()              ← OZ v5 hook (replaces _beforeTokenTransfer)
      → if to != address(0):
          → ComplianceModule.canTransfer(from, to, trancheId)
              → validates receiver (always)
              → validates sender (only when from != address(0))
              → allow / revert
      → super._update()               ← balances updated
      → checkpoint new balances        ← for dividend snapshot queries
```

**Exception:** `forceTransfer()` bypasses this hook entirely by calling `super._update()` directly. This is intentional — it is the only path that skips compliance, and it is restricted to `DEFAULT_ADMIN_ROLE`.

This guarantees:

* Non-allowlisted users can never receive tokens (including via mint)
* Frozen or restricted users cannot bypass rules
* Backend failures cannot violate compliance
* Balance history is always in sync with transfers for accurate dividend snapshots
* Minting respects per-tranche supply caps (`maxSupply`)

---

## 6. Primary Market & Payment Flow

### Subscription-Based Issuance

1. Investor submits subscription request via `requestSubscription(trancheId, amount)`
2. Investor may cancel a pending request via `cancelSubscription(trancheId)` before approval
3. Backend verifies:

   * KYC completed
   * Off-chain payment settled
4. Issuer/admin approves subscription via `approveSubscription(investor, trancheId)`
5. IssuanceModule mints tranche tokens on-chain (subject to `maxSupply` cap)

### Payment Handling

* Stablecoin settlement preferred (e.g., USDC)
* Fiat settlement assumed off-chain
* Backend reconciles off-chain payments with on-chain mint approvals
* On-chain minting only occurs after approval

---

## 7. Corporate Actions Design

### Dividend / Coupon Distribution

* Each declaration creates a new **round/epoch** — `currentRound[trancheId]` increments on every call
* `snapshotBlock = block.number` is stored at declaration time
* Investors call `claimDividend(trancheId, round)` to pull their payout
* Payout uses `balanceOfAt(investor, trancheId, snapshotBlock)` — balance **at the record date**, not at claim time
* Payment is made in stablecoin via `IERC20.transfer` (e.g. USDC) — no native ETH involved
* `claimed[trancheId][round][investor]` prevents double-claiming per round
* `claimDividend` is protected by both CEI pattern and `nonReentrant` guard

#### Rationale

* Avoids O(n) loops — gas-efficient for large holder sets
* Epoch model allows multiple undeclared dividends to coexist without overwriting
* Snapshot prevents gaming (buying tokens after declaration to claim without holding at record date)
* Stablecoin payouts align with RWA operational reality
* Dual reentrancy protection (CEI + ReentrancyGuard) demonstrates defense-in-depth

---

## 8. Observability & Event Processing

### On-Chain Events

| Contract                | Events                                                          |
| ----------------------- | --------------------------------------------------------------- |
| AssetToken              | `Minted`, `Burned`, `MaxSupplySet`, `ForcedTransfer`            |
| ComplianceModule        | `InvestorUpdated`, `InvestorFrozen`, `TrancheRequirementUpdated` |
| IssuanceModule          | `SubscriptionRequested`, `SubscriptionCancelled`, `SubscriptionApproved` |
| CorporateActionsModule  | `DividendDeclared`, `DividendClaimed`                           |

### Backend Consumers

* Index transfers for audit trail
* Generate investor statements
* Support reconciliation & reporting
* Monitor anomalies (e.g., failed transfers, forced transfers)

Events serve as the **canonical audit log**.

---

## 9. Upgradeability & Governance

### Upgrade Pattern

All contracts use the **UUPS (Universal Upgradeable Proxy Standard)** pattern with **ERC-7201 namespaced storage** for collision-safe upgrades:

* Each contract's state variables are packed into a single `struct` stored at a deterministic slot computed via `keccak256(abi.encode(uint256(keccak256("rwa.storage.<ContractName>")) - 1)) & ~bytes32(uint256(0xff))`
* Constructors are replaced with `initialize()` functions using the `initializer` modifier
* Implementation constructors call `_disableInitializers()` to prevent re-initialization
* Upgrade authorization is gated by `UPGRADER_ROLE` via `_authorizeUpgrade()` override

### ERC-7201 Storage Namespaces

| Contract | Namespace |
| --- | --- |
| AssetToken | `rwa.storage.AssetToken` |
| ComplianceModule | `rwa.storage.ComplianceModule` |
| IssuanceModule | `rwa.storage.IssuanceModule` |
| CorporateActionsModule | `rwa.storage.CorporateActionsModule` |

### Governance Controls

* Multisig / MPC admin keys (recommended for production)
* `UPGRADER_ROLE` — dedicated role for contract upgrades, separate from operational roles
* Emergency pause functionality (implemented)
* Forced transfer capability for regulatory compliance (implemented)
* Role separation: `DEFAULT_ADMIN_ROLE`, `ISSUER_ROLE`, `COMPLIANCE_ADMIN_ROLE`, `ADMIN_ROLE`, `UPGRADER_ROLE`

Upgrades are assumed to be **rare, reviewed, and governed**.

---

## 10. Security Model & Threat Considerations

### Key Threats Addressed

* Unauthorized minting → `ISSUER_ROLE` + `maxSupply` cap
* Compliance bypass → `_update` hook enforcement on all transfers
* Admin key compromise → role separation, multisig recommendation
* Reentrancy in payouts → CEI pattern + `ReentrancyGuard`
* Forced transfer abuse → `DEFAULT_ADMIN_ROLE` only, `ForcedTransfer` event emitted
* Storage collision during upgrades → ERC-7201 namespaced storage prevents collisions

### Mitigations

* Role-based access control (OpenZeppelin `AccessControl`)
* On-chain compliance enforcement via transfer hooks
* Pausable contracts for emergency response
* Minimal trusted roles with clear separation
* `ReentrancyGuard` on payout paths
* All state-changing functions emit events for audit

---

## 11. Privacy Considerations

* No PII stored on-chain
* Investors represented by addresses only
* Backend stores KYC references, not raw data
* Jurisdiction & investor type encoded as enums (numeric codes)

---

## 12. Assumptions

* Single EVM-compatible chain
* Hybrid custody model (custodial issuers, self-custody investors)
* Stablecoin-based settlement (e.g. USDC)
* Issuers and platform operator are permissioned
* Admin keys secured via multisig or MPC in production

All assumptions are explicitly stated to avoid hidden trust dependencies.

---

## 13. Summary

This architecture delivers:

* Hard compliance guarantees enforced on-chain
* Modular contracts with clean interface inheritance
* Tranche-aware RWA modeling with per-tranche supply caps
* Regulatory intervention capability (forced transfers, freeze, pause)
* Operationally realistic workflows (subscription cancellation, investor data queries)
* Defense-in-depth security (CEI + ReentrancyGuard, role separation)
* Clear separation of responsibilities across all layers

The design is intentionally pragmatic, secure, and suitable for incremental production rollout.

---
