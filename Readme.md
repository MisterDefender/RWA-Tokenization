# 🏛️ RWA Tokenization Platform (ERC-1155 Tranches)

## 📋 Overview

This repository presents a **Real-World Asset (RWA) tokenization platform** built on an EVM-compatible blockchain.

The system supports:

* 🪙 Asset issuance with **tranche-based tokenization** (ERC-1155)
* 🔒 On-chain **compliance-enforced transfers** via `_update` hook
* 📝 Primary market subscription flows (with cancellation)
* 🔄 Secondary market transfers
* 💰 Corporate actions (snapshot-based dividends with claim model)
* 🛑 Operational controls (pause, freeze, forced transfer)
* 📊 Per-tranche supply caps

The design prioritizes **regulatory compliance, security, and operational realism**.

---

## 🏗️ Architecture Summary

```
Frontend (HTML/JS)
        |
Smart Contracts (EVM)
        |
Compliance Enforcement (On-Chain via _update hook)
        |
Backend (Node.js - Coordination & Observability)
```

### Key Principles

* ⛓️ **On-chain is the source of truth**
* 🛡️ **Compliance is enforced at the protocol level** (inside `_update` hook)
* 🚫 Backend cannot bypass smart-contract rules
* 🔐 No PII is stored on-chain

---

## 🪙 Token Model

* **ERC-1155** is used to represent assets with **multiple tranches/classes**
* Each tranche has:

  * Its own token ID
  * Independent compliance rules (jurisdiction, investor type)
  * Distinct economic rights
  * Optional supply cap (`maxSupply`)

Example:

| Token ID | Tranche |
| -------- | ------- |
| 1        | Senior  |
| 2        | Junior  |
| 3        | Equity  |

---

## 📜 Smart Contracts

Located in [`/contracts`](contracts/)

All contracts implement their corresponding interfaces defined in [`/contracts/Interfaces/`](contracts/Interfaces/) using Solidity's `is` keyword.

| Contract | Interface | Responsibility |
| --- | --- | --- |
| [`AssetToken.sol`](contracts/AssetToken.sol) | [`IAssetToken`](contracts/Interfaces/IAssetToken.sol) | ERC-1155 token, transfer hooks, snapshots |
| [`ComplianceModule.sol`](contracts/ComplianceModule.sol) | [`IComplianceModule`](contracts/Interfaces/IComplianceModule.sol) | Allowlist, jurisdiction, investor type |
| [`IssuanceModule.sol`](contracts/IssuanceModule.sol) | [`IIssuanceModule`](contracts/Interfaces/IIssuanceModule.sol) | Subscription & primary issuance |
| [`CorporateActionsModule.sol`](contracts/CorporateActionsModule.sol) | [`ICorporateActions`](contracts/Interfaces/ICorporateActions.sol) | Dividends / coupons (claim-based, snapshot) |

### ✨ Key Features

* 🛡️ **Compliance enforcement** via OZ v5 `_update` hook — all transfers validated on-chain
* 📊 **Per-tranche supply caps** — `maxSupply` prevents over-minting
* ⚖️ **Forced transfer** — `DEFAULT_ADMIN_ROLE` can bypass compliance for regulatory intervention
* 📸 **Snapshot-based dividends** — `balanceOfAt()` for accurate record-date accounting
* ❌ **Subscription cancellation** — investors can cancel pending requests
* 🧊 **Frozen state preservation** — `setInvestor()` never accidentally unfreezes
* 🔐 **Defense-in-depth** — CEI pattern + ReentrancyGuard on dividend claims
* 🔍 **`getInvestor()` view** — query investor compliance data on-chain
* 🔄 **UUPS upgradeable** — all contracts use ERC-7201 namespaced storage

### 🔒 Compliance Enforcement

All transfers flow through the `_update` hook:

```
_update(from, to, ids, values)
    -> if to != address(0):
        -> ComplianceModule.canTransfer(from, to, trancheId)
            -> validates receiver (always)
            -> validates sender (only when from != address(0))
            -> allow / revert
    -> super._update()              // balances updated
    -> checkpoint new balances      // for dividend snapshot queries
```

Exception: `forceTransfer()` bypasses this hook — restricted to `DEFAULT_ADMIN_ROLE`.

---

## ⚙️ Backend (Node.js)

Located in [`/backend`](backend/)

The backend is **not a trust anchor**.
Its responsibilities include:

* 🪪 KYC coordination
* 🌍 Jurisdiction tagging
* ✅ Subscription approval
* 📡 Event indexing
* 📋 Audit & reconciliation support

---

## 🖥️ Frontend

Located in [`/frontend`](frontend/)

* Plain HTML/CSS/JS
* Wallet-based interactions only
* Minimal UI by design

The frontend exists to demonstrate flows, not visual polish.

---

## 📚 Documentation

| Document | Description |
| --- | --- |
| 🏗️ [Architecture](docs/architecture.md) | System architecture & reasoning |
| 🔄 [Sequence Diagrams](docs/sequence-diagrams.md) | Core system flows |
| 💾 [Data Model](docs/data-model.md) | On-chain vs off-chain data |
| 🛡️ [Compliance Model](docs/compliance-model.md) | Compliance enforcement design |
| ⚠️ [Risk Register](docs/risk-register.md) | Top risks & mitigations |
| 🧪 [Test Plan](test-plan.md) | Test & verification strategy |

---

## 🔐 Security & Operations

* 🔄 **UUPS upgradeable** contracts with **ERC-7201 namespaced storage** — collision-safe upgrades
* 👥 Role-based access control (`DEFAULT_ADMIN_ROLE`, `ISSUER_ROLE`, `COMPLIANCE_ADMIN_ROLE`, `ADMIN_ROLE`, `UPGRADER_ROLE`)
* 🛑 Emergency pause & freeze mechanisms
* ⚖️ Forced transfer capability for regulatory compliance
* 📊 Per-tranche supply caps (`maxSupply`)
* 💰 Claim-based corporate actions with snapshot accounting
* 📋 Event-driven audit trail
* 🔐 Defense-in-depth: CEI + ReentrancyGuard on payout paths

---

## 📌 Assumptions

* Single EVM-compatible chain
* Stablecoin settlement preferred (e.g. USDC)
* Custodial issuer wallets (MPC / multisig)
* Permissioned issuers
* Hybrid investor custody model

All assumptions are explicitly stated to avoid hidden trust dependencies.

---

## 🧭 How to Navigate

1. Start with 🏗️ [Architecture](docs/architecture.md)
2. Review 🛡️ [Compliance Model](docs/compliance-model.md)
3. Inspect 📜 [Contract Interfaces](contracts/Interfaces/)
4. Review 🔄 [Sequence Diagrams](docs/sequence-diagrams.md)
5. Review ⚠️ [Risk Register](docs/risk-register.md)
6. Review 🧪 [Test Plan](test-plan.md)

---
