# Compliance Model

## 1. Objective

The compliance model ensures that:

* Only KYC-approved investors can hold tokens
* Jurisdictional restrictions are enforced
* Investor-type restrictions (Retail / Accredited / Institutional) are respected
* Transfers can be paused or frozen when required
* Regulatory intervention is technically enforceable (forced transfers implemented)

Most importantly:

> Compliance is enforced **on-chain**, not via backend checks.

---

## 2. Compliance Enforcement Architecture

### Enforcement Layer

Compliance is enforced inside the OZ v5 `_update` hook (which replaced `_beforeTokenTransfer`):

```solidity
_update(from, to, ids, values)               // OZ v5 hook
    → if to != address(0):
        → compliance.canTransfer(from, to, trancheId)
            → validates receiver always (covers mints and transfers)
            → validates sender only when from != address(0)
            → allow / revert
    → super._update()                        // balances updated
    → checkpoint balances per address/tranche // for dividend snapshot queries
```

**Exception:** `forceTransfer()` bypasses this hook entirely by calling `super._update()` directly. This is intentional — it is the only path that skips compliance, and it is restricted to `DEFAULT_ADMIN_ROLE`.

This guarantees:

* Non-allowlisted addresses cannot receive tokens — including via direct minting
* Frozen addresses cannot send or receive
* Jurisdiction rules cannot be bypassed
* Backend downtime cannot weaken enforcement
* Balance checkpoints are always in sync for accurate dividend snapshot queries

---

## 3. Compliance Dimensions

### 3.1 Allowlist (KYC/AML)

**Rule:**
An address must be explicitly allowlisted before receiving tokens.

**On-chain State:**

```solidity
mapping(address => InvestorData) investors;

struct InvestorData {
    bool allowlisted;
    bool frozen;
    uint8 jurisdiction;
    InvestorType investorType;
}
```

**Flow:**

1. Investor completes KYC off-chain
2. Backend verifies KYC provider result
3. Compliance admin calls `setInvestor()` on-chain

No raw identity data is stored on-chain.

---

### 3.2 Jurisdiction Restrictions

Each investor has a jurisdiction code:

```solidity
uint8 jurisdiction;
```

Each tranche may define:

```solidity
requiredJurisdiction[trancheId]
```

**Transfer Rule:**

```
receiver.jurisdiction == requiredJurisdiction[trancheId]
```

This supports:

* Country-based distribution limits
* Cross-border regulatory compliance
* Region-specific tranches

A `TrancheRequirementUpdated` event is emitted when tranche rules are changed.

---

### 3.3 Investor Type Restrictions

Investor types are defined in `IComplianceModule` and shared across all contracts:

```solidity
enum InvestorType {
    NONE,
    RETAIL,
    ACCREDITED,
    INSTITUTIONAL
}
```

Each tranche may require a minimum or specific type.

Example:

* Senior tranche → Institutional only
* Junior tranche → Accredited+
* Equity → Retail allowed

This supports securities law distinctions.

---

### 3.4 Freeze Mechanism

Admin may freeze a specific address:

```solidity
freeze(address investor, bool status)
```

Frozen addresses:

* Cannot transfer
* Cannot receive

**Important:** `setInvestor()` **preserves existing frozen state** — updating jurisdiction or investor type will not accidentally unfreeze an investor. Use `freeze()` explicitly to change frozen status.

Use cases:

* Sanctions update
* Fraud investigation
* Regulatory intervention

---

### 3.5 Pause Mechanism

Global pause blocks all transfers (except forced transfers).

Use cases:

* Contract upgrade
* Security incident
* Regulatory directive

---

### 3.6 Forced Transfers (Implemented)

Forced transfer capability is implemented in `AssetToken`:

```solidity
forceTransfer(from, to, trancheId, amount)
    → restricted to DEFAULT_ADMIN_ROLE
    → bypasses compliance checks and pause state
    → calls super._update() directly
    → manually updates balance checkpoints
    → emits ForcedTransfer event
```

Use cases:

* Court order
* Regulatory clawback
* Custody recovery

Mitigations:

* Restricted to `DEFAULT_ADMIN_ROLE` only
* `ForcedTransfer` event emitted for audit trail
* Logged permanently on-chain
* Bypasses compliance intentionally — this is the only code path that does

---

### 3.7 Investor Data Query

The `getInvestor()` view function allows backend, frontend, and other contracts to query investor compliance data:

```solidity
function getInvestor(address investor)
    external view
    returns (bool allowlisted, bool frozen, uint8 jurisdiction, InvestorType investorType);
```

This enables off-chain systems to check compliance status without modifying state.

---

## 4. Off-Chain Compliance Layer

The backend handles:

* KYC provider integration
* Sanctions list checks
* Ongoing monitoring
* Payment reconciliation

However:

> Backend cannot override on-chain compliance checks.

The smart contract remains the final enforcement authority.

---

## 5. Compliance State Lifecycle

### Investor Onboarding

1. Investor submits documents
2. KYC provider verifies identity
3. Backend records approval
4. ComplianceModule.setInvestor(...) called on-chain

### Secondary Transfer

1. User initiates ERC-1155 transfer
2. ComplianceModule validates:

   * Allowlisted
   * Not frozen
   * Jurisdiction match
   * Investor-type match
3. Transfer succeeds or reverts

---

## 6. Hard Guarantees

The system guarantees:

1. Non-allowlisted users can never receive tokens.
2. Frozen users cannot transact.
3. Jurisdiction-restricted tranches cannot leak cross-border.
4. Investor-type requirements cannot be bypassed.
5. Compliance enforcement survives backend failure.
6. `setInvestor()` never accidentally unfreezes a frozen investor.
7. Forced transfers are the **only** path that bypasses compliance — restricted to `DEFAULT_ADMIN_ROLE`.

---

## 7. Upgrade & Regulatory Adaptability

All contracts use the **UUPS proxy pattern** with **ERC-7201 namespaced storage**, enabling governed upgrades without storage collision risk.

Compliance rules are modular:

* ComplianceModule is upgradeable via UUPS — `UPGRADER_ROLE` required
* Tranche requirements configurable via `setTrancheRequirements()`
* Investor types extensible via the `InvestorType` enum in `IComplianceModule`
* ERC-7201 storage namespace: `rwa.storage.ComplianceModule`

---

## 8. Audit & Traceability

All compliance changes emit events:

* `InvestorUpdated` — when investor data is set or changed
* `InvestorFrozen` — when an investor is frozen or unfrozen
* `TrancheRequirementUpdated` — when tranche jurisdiction/investor-type rules change
* `ForcedTransfer` — when a forced transfer is executed (emitted by AssetToken)

These provide:

* Full regulatory audit trail
* Forensic analysis capability
* Operational transparency

---

## 9. Design Rationale Summary

The compliance model:

* Enforces rules at the protocol layer via `_update` hook
* Separates identity from settlement
* Avoids PII on-chain
* Supports real-world securities regulation
* Preserves frozen state across investor data updates
* Provides forced transfer capability for regulatory intervention
* Exposes investor data via `getInvestor()` for off-chain coordination

---
