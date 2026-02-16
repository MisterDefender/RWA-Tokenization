# Risk Register

This section identifies key **technical, operational, and regulatory risks** associated with the RWA tokenization platform and outlines mitigation strategies.

---

## 1. Admin Key Compromise

**Risk**
Compromise of issuer or platform admin keys could enable unauthorized minting, freezing, or pausing.

**Impact**
Catastrophic — loss of asset integrity and regulatory trust.

**Mitigation**

* Use MPC or multisig wallets for admin roles
* Enforce role separation (`DEFAULT_ADMIN_ROLE`, `ISSUER_ROLE`, `COMPLIANCE_ADMIN_ROLE`, `ADMIN_ROLE`)
* Time-delayed sensitive actions
* Continuous monitoring of admin transactions
* `forceTransfer` restricted to `DEFAULT_ADMIN_ROLE` only — emits `ForcedTransfer` event for audit

---

## 2. Compliance Logic Bypass

**Risk**
Incorrect integration of compliance checks could allow non-allowlisted transfers.

**Impact**
Regulatory violation and legal exposure.

**Mitigation**

* Enforce compliance in the OZ v5 `_update` hook — all transfers, mints, and burns flow through this hook
* `canTransfer(from, to, trancheId)` validates receiver always; validates sender only when `from != address(0)` (mint-safe)
* Do not rely on backend checks
* Explicit invariants in tests
* `forceTransfer()` is the **only** code path that bypasses compliance — intentionally restricted to `DEFAULT_ADMIN_ROLE`

---

## 3. Incorrect Jurisdiction or Investor Classification

**Risk**
Off-chain misclassification leads to improper on-chain permissions.

**Impact**
Unauthorized access or blocked legitimate transfers.

**Mitigation**

* Dual control for compliance updates
* Clear audit logs via `InvestorUpdated` and `TrancheRequirementUpdated` events
* `getInvestor()` view function enables reconciliation between backend and on-chain state
* `setInvestor()` preserves frozen state — updating classification cannot accidentally unfreeze an investor
* Ability to freeze addresses rapidly

---

## 4. Upgradeability Risks (Storage Collision)

**Risk**
Contract upgrades may corrupt state if storage layouts are incompatible.

**Impact**
Permanent asset loss or protocol failure.

**Mitigation**

* All contracts use **UUPS proxy pattern** with **ERC-7201 namespaced storage** — deterministic storage slots prevent collisions
* Upgrades gated by `UPGRADER_ROLE` — separate from operational roles
* Each contract's state stored in a dedicated namespace (e.g. `rwa.storage.AssetToken`)
* Pre-upgrade simulation recommended
* Limit upgrade frequency

---

## 5. Corporate Action Gas Exhaustion

**Risk**
Dividend or redemption logic may become too expensive with many holders.

**Impact**
Inability to execute corporate actions.

**Mitigation**

* Claim-based pull distribution model — investors call `claimDividend()` individually
* No unbounded loops — O(1) per claim
* Gas-cost testing under load assumptions
* Epoch/round model allows multiple concurrent dividends without overwriting

---

## 6. Custody Provider Failure

**Risk**
Custodial wallet outage or compromise prevents issuer actions.

**Impact**
Operational downtime or asset mismanagement.

**Mitigation**

* Redundant custody signers
* Emergency pause controls
* `forceTransfer()` capability for custody recovery (restricted to `DEFAULT_ADMIN_ROLE`)
* Disaster recovery procedures
* Clear custody SLAs

---

## 7. Event Indexing Failure

**Risk**
Backend misses events, leading to reconciliation gaps or incorrect statements.

**Impact**
Audit inconsistencies and reporting errors.

**Mitigation**

* Idempotent event ingestion
* Re-indexing from block ranges
* On-chain state remains canonical
* All critical actions emit events: `Minted`, `Burned`, `MaxSupplySet`, `ForcedTransfer`, `InvestorUpdated`, `InvestorFrozen`, `TrancheRequirementUpdated`, `SubscriptionRequested`, `SubscriptionCancelled`, `SubscriptionApproved`, `DividendDeclared`, `DividendClaimed`

---

## 8. Regulatory Rule Changes

**Risk**
New regulations require changes to transfer restrictions or investor eligibility.

**Impact**
Protocol non-compliance.

**Mitigation**

* Externalized compliance module — `ComplianceModule` is a separate contract
* Configurable tranche rules via `setTrancheRequirements()`
* `InvestorType` enum defined in `IComplianceModule` interface — extensible
* Architecture is proxy-ready for future upgrade if needed

---

## 9. Forced Transfer Abuse

**Risk**
Admin-initiated forced transfers could be misused.

**Impact**
Loss of investor trust.

**Mitigation**

* `forceTransfer()` restricted to `DEFAULT_ADMIN_ROLE` only
* `ForcedTransfer` event emitted on-chain for permanent audit trail
* Bypasses compliance intentionally — clearly documented as the only such path
* Governance approval or time-lock recommended for production
* Clear policy disclosure to investors

---

## 10. Backend Outage

**Risk**
Backend downtime prevents onboarding or issuance approvals.

**Impact**
Temporary operational disruption.

**Mitigation**

* Stateless backend design
* Retryable workflows
* Smart contracts remain functional for transfers and dividend claims
* `getInvestor()` enables independent on-chain compliance queries

---

## 11. Frontend Spoofing or Phishing

**Risk**
Users interact with malicious frontends.

**Impact**
Loss of funds or credentials.

**Mitigation**

* Encourage wallet verification prompts
* Publish verified contract addresses
* Educate users on trusted URLs

---

## 12. Inconsistent Off-Chain / On-Chain State

**Risk**
Payment settled off-chain but minting fails on-chain (or vice versa).

**Impact**
Financial reconciliation issues.

**Mitigation**

* Explicit approval-based minting — `approveSubscription()` required before mint
* `cancelSubscription()` allows investors to withdraw pending requests
* Manual reconciliation workflows
* Clear transaction state machine
* `maxSupply` cap prevents over-minting even if backend errors occur

---

## 13. Reentrancy in Dividend Payouts

**Risk**
Malicious ERC20 token or callback attempts to re-enter `claimDividend()`.

**Impact**
Drain of dividend funds or double-claiming.

**Mitigation**

* CEI (Checks-Effects-Interactions) pattern: `claimed` state updated before external `transfer` call
* `nonReentrant` modifier (OpenZeppelin `ReentrancyGuard`) on `claimDividend()` for defense-in-depth
* Dual protection ensures safety even if one layer is bypassed

---

## 14. Supply Cap Violation

**Risk**
Minting exceeds intended supply for a tranche.

**Impact**
Dilution of existing holders, regulatory non-compliance.

**Mitigation**

* `maxSupply` per-tranche cap enforced on-chain in `mint()` — cannot be bypassed by backend
* `setMaxSupply()` restricted to `ADMIN_ROLE`
* `MaxSupplySet` event emitted for audit trail
* Cap of 0 means unlimited (explicit design choice)

---

## Summary

This risk register demonstrates:

* Awareness of real-world operational threats
* Strong on-chain mitigations with defense-in-depth
* Pragmatic, non-idealized assumptions
* Production-oriented thinking
* Complete event coverage for audit and monitoring

The platform is designed to **fail safely**, preserve compliance guarantees, and enable controlled recovery from incidents.

---
