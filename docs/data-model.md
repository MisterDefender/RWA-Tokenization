# Data Model

## 1. Design Principles

The data model is designed around the following principles:

* **On-chain = enforcement & settlement**
* **Off-chain = identity, compliance evidence, coordination**
* **No PII stored on-chain**
* **Event-driven synchronization**
* **Backend is not a source of truth for compliance**

---

## 2. On-Chain Data Model

### 2.1 AssetToken (ERC-1155)

| Field | Type | Description |
| --- | --- | --- |
| `tokenId` | `uint256` | Tranche identifier |
| `balanceOf` | mapping | Investor balances per tranche |
| `totalSupply` | mapping | Total supply per tranche |
| `maxSupply` | mapping | Per-tranche supply cap (0 = unlimited) |
| `paused` | bool | Global transfer pause |
| `_balanceCheckpoints` | mapping | Per-address per-tranche `Checkpoints.Trace208` for snapshot queries |

**Notes**

* Token ID uniquely represents a tranche/class
* Asset metadata referenced off-chain via URI
* Balances are canonical ownership records
* `maxSupply` enforces a hard ceiling on minting per tranche — `setMaxSupply(trancheId, cap)` restricted to `ADMIN_ROLE`
* Balance checkpoints enable `balanceOfAt(account, trancheId, blockNumber)` for historical queries (used by dividend snapshots)

---

### 2.2 ComplianceModule

| Field | Type | Description |
| --- | --- | --- |
| `investors` | mapping(address => InvestorData) | Per-address compliance data |
| `InvestorData.allowlisted` | bool | KYC approval status |
| `InvestorData.frozen` | bool | Transfer freeze flag |
| `InvestorData.jurisdiction` | uint8 | Encoded jurisdiction (no PII) |
| `InvestorData.investorType` | InvestorType enum | NONE / RETAIL / ACCREDITED / INSTITUTIONAL |
| `requiredJurisdiction` | mapping(uint256 => uint8) | Tranche-specific jurisdiction rule |
| `requiredInvestorType` | mapping(uint256 => InvestorType) | Tranche-specific investor type rule |

**Notes**

* `InvestorType` enum is defined in `IComplianceModule` and shared across all contracts
* `setInvestor()` preserves existing frozen state — updating jurisdiction or investor type will not accidentally unfreeze an investor
* `getInvestor()` view function exposes compliance data for off-chain queries
* Compliance logic enforced on transfer hooks via `canTransfer(from, to, trancheId)`

---

### 2.3 IssuanceModule

| Field | Type | Description |
| --- | --- | --- |
| `subscriptions[investor][trancheId]` | Subscription struct | Pending issuance requests |
| `Subscription.amount` | uint256 | Requested quantity |
| `Subscription.approved` | bool | Issuer approval status |

**Notes**

* Per-tranche subscriptions: an investor may have concurrent pending requests across different tranches
* `requestSubscription` requires `amount > 0`
* Investors can cancel pending (unapproved) subscriptions via `cancelSubscription(trancheId)`
* Prevents unauthorized minting — only `ISSUER_ROLE` can approve
* Mirrors off-chain subscription workflows

---

### 2.4 CorporateActionsModule

| Field | Type | Description |
| --- | --- | --- |
| `currentRound` | mapping(uint256 => uint256) | Latest round number per tranche |
| `dividendRounds` | mapping (3-level) | Per-round `DividendRound` struct |
| `DividendRound.amountPerToken` | uint256 | Stablecoin units paid per token |
| `DividendRound.snapshotBlock` | uint48 | Block number at record date |
| `claimed` | mapping (3-level) | Claim status per investor per round |
| `paymentToken` | IERC20 | Stablecoin contract (e.g. USDC) |

**Notes**

* Epoch/round model: each `declareDividend` increments `currentRound[trancheId]` — previous unclaimed rounds are never overwritten
* `declareDividend` requires `amountPerToken > 0`
* Snapshot-based accounting: `snapshotBlock` fixed at declaration; `claimDividend` calls `token.balanceOfAt(investor, trancheId, snapshotBlock)` to read balance at record date
* Stablecoin payouts via `IERC20` — no native ETH
* Three-level `claimed` mapping prevents double-claiming across multiple concurrent rounds
* Claim-based pull model avoids O(n) loops and gas exhaustion
* `claimDividend` protected by both CEI pattern and `nonReentrant` (ReentrancyGuard) for defense-in-depth

---

## 3. On-Chain Events

| Contract | Events |
| --- | --- |
| AssetToken | `Minted`, `Burned`, `MaxSupplySet`, `ForcedTransfer` |
| ComplianceModule | `InvestorUpdated`, `InvestorFrozen`, `TrancheRequirementUpdated` |
| IssuanceModule | `SubscriptionRequested`, `SubscriptionCancelled`, `SubscriptionApproved` |
| CorporateActionsModule | `DividendDeclared`, `DividendClaimed` |

---

## 4. Off-Chain Data Model (Backend)

### 4.1 Issuer

```json
{
  "issuerId": "uuid",
  "name": "Issuer Entity Name",
  "custodyWallet": "0x...",
  "status": "ACTIVE",
  "createdAt": "timestamp"
}
```

**Notes**

* Issuer identity verified off-chain
* Wallet may be MPC or multisig

---

### 4.2 Investor

```json
{
  "investorId": "uuid",
  "wallet": "0x...",
  "kycStatus": "APPROVED",
  "jurisdictionCode": 356,
  "investorType": "ACCREDITED",
  "kycProviderRef": "external-id"
}
```

**Notes**

* No raw identity documents stored
* Backend maps KYC outcome → on-chain flags via `setInvestor()`

---

### 4.3 Asset

```json
{
  "assetId": "uuid",
  "issuerId": "uuid",
  "name": "Commercial Real Estate Fund",
  "metadataURI": "ipfs://...",
  "status": "ISSUED"
}
```

**Notes**

* Legal docs referenced via URI
* Metadata never stored on-chain

---

### 4.4 Tranche

```json
{
  "trancheId": 1,
  "assetId": "uuid",
  "name": "Senior Tranche",
  "rights": ["PRIORITY_COUPON"],
  "jurisdictionRestriction": 356,
  "investorTypeRestriction": "INSTITUTIONAL",
  "maxSupply": 1000000
}
```

---

### 4.5 Subscription / Order

```json
{
  "orderId": "uuid",
  "investorId": "uuid",
  "assetId": "uuid",
  "trancheId": 1,
  "amount": 1000,
  "status": "PENDING | APPROVED | CANCELLED",
  "paymentStatus": "SETTLED",
  "onChainTx": "0x..."
}
```

**Notes**

* Backend reconciles payment → minting
* On-chain tx hash stored for audit
* Status tracks subscription lifecycle including cancellation

---

### 4.6 Events (Indexed)

```json
{
  "eventType": "TRANSFER | MINT | BURN | FORCED_TRANSFER | DIVIDEND_DECLARED | DIVIDEND_CLAIMED | SUBSCRIPTION_CANCELLED",
  "txHash": "0x...",
  "from": "0x...",
  "to": "0x...",
  "trancheId": 1,
  "timestamp": "blockTime"
}
```

**Notes**

* Derived exclusively from on-chain logs
* Used for statements and reconciliation
* `FORCED_TRANSFER` events flagged separately for monitoring and audit

---

## 5. On-Chain vs Off-Chain Boundary Summary

| Category               | On-Chain    | Off-Chain   |
| ---------------------- | ----------- | ----------- |
| Ownership              | Yes         | No          |
| Compliance enforcement | Yes         | No          |
| KYC evidence           | No          | Yes         |
| Jurisdiction logic     | Yes (encoded) | Yes (source) |
| Payments (fiat)        | No          | Yes         |
| Audit trail            | Yes (events) | Yes (indexed) |
| Supply caps            | Yes         | Yes (config) |

---

## 6. Data Integrity Guarantees

* Backend failures cannot break compliance
* On-chain state always authoritative
* Events provide immutable audit trail
* No sensitive data exposed publicly
* `setInvestor()` preserves frozen state — no accidental data corruption
* `maxSupply` enforced on-chain — backend cannot mint beyond cap

---

## 7. Summary

This data model ensures:

* Strong regulatory compliance
* Clear trust boundaries
* Minimal on-chain storage
* Operational scalability
* Defense-in-depth for critical state (frozen preservation, supply caps, reentrancy protection)

The separation enables secure iteration without compromising protocol guarantees.

---
