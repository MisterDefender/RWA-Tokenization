# Sequence Diagrams
----

### Asset Onboarding & Tranche Setup

```mermaid

sequenceDiagram
    participant Issuer
    participant Backend
    participant ComplianceModule
    participant AssetToken

    Issuer->>Backend: Submit asset metadata (off-chain)
    Backend->>ComplianceModule: setTrancheRequirements(trancheId, rules)
    Note over ComplianceModule: Emits TrancheRequirementUpdated event
    Backend->>AssetToken: setMaxSupply(trancheId, cap)
    Note over AssetToken: Emits MaxSupplySet event
    Backend->>AssetToken: Assign ISSUER_ROLE
    Note over ComplianceModule: Jurisdiction & investor-type rules stored on-chain


```

### Investor Onboarding & Primary Subscription
#### Investor subscribes, issuer approves, tokens are minted.

```mermaid
sequenceDiagram
    participant Investor
    participant Frontend
    participant Backend
    participant IssuanceModule
    participant AssetToken

    Investor->>Frontend: Connect wallet
    Investor->>Frontend: Request subscription
    Frontend->>IssuanceModule: requestSubscription(trancheId, amount)
    Note over IssuanceModule: Requires amount > 0<br/>Stored at subscriptions[investor][trancheId]

    Backend->>Backend: Perform KYC / payment checks
    Backend->>ComplianceModule: setInvestor(investor, true, jurisdiction, investorType)
    Note over ComplianceModule: Investor allowlisted on-chain<br/>Emits InvestorUpdated event

    Backend->>IssuanceModule: approveSubscription(investor, trancheId)

    IssuanceModule->>AssetToken: mint(investor, trancheId, amount)
    Note over AssetToken: _update hook checks compliance<br/>(receiver must be allowlisted)<br/>maxSupply cap enforced

```

### Subscription Cancellation
#### Investor cancels a pending (unapproved) subscription.

```mermaid
sequenceDiagram
    participant Investor
    participant Frontend
    participant IssuanceModule

    Investor->>Frontend: Cancel subscription
    Frontend->>IssuanceModule: cancelSubscription(trancheId)
    Note over IssuanceModule: Requires pending subscription exists<br/>(amount > 0 && !approved)
    IssuanceModule->>IssuanceModule: delete subscriptions[investor][trancheId]
    Note over IssuanceModule: Emits SubscriptionCancelled event

```

### Secondary Transfer With Compliance Enforcement
#### Enforce allowlist, jurisdiction, and freeze rules on-chain.

```mermaid
sequenceDiagram
    participant InvestorA
    participant InvestorB
    participant AssetToken
    participant ComplianceModule

    InvestorA->>AssetToken: safeTransferFrom(A, B, trancheId)
    AssetToken->>ComplianceModule: canTransfer(A, B, trancheId)

    alt Compliant
        ComplianceModule-->>AssetToken: true
        Note over AssetToken: Checkpoint balances updated
        AssetToken-->>InvestorB: Transfer success
    else Not compliant
        ComplianceModule-->>AssetToken: false
        AssetToken-->>InvestorA: Revert transaction
    end
```

### Corporate Action – Dividend Distribution (Claim-Based, Snapshot)

#### Epoch-based rounds with snapshot balances — no holder iteration required

```mermaid
sequenceDiagram
    participant Issuer
    participant CorporateActionsModule
    participant AssetToken
    participant Investor
    participant USDC

    Issuer->>CorporateActionsModule: declareDividend(trancheId, amountPerToken)
    Note over CorporateActionsModule: Requires amountPerToken > 0<br/>currentRound[trancheId]++<br/>snapshotBlock = block.number<br/>New round created — previous rounds unaffected

    Investor->>CorporateActionsModule: claimDividend(trancheId, round)
    Note over CorporateActionsModule: Protected by nonReentrant guard
    CorporateActionsModule->>AssetToken: balanceOfAt(investor, trancheId, snapshotBlock)
    Note over AssetToken: Returns balance at record-date block<br/>not current balance
    AssetToken-->>CorporateActionsModule: balance at snapshot

    CorporateActionsModule->>CorporateActionsModule: claimed[trancheId][round][investor] = true
    Note over CorporateActionsModule: CEI pattern: state updated before external call
    CorporateActionsModule->>USDC: transfer(investor, balance * amountPerToken)
    USDC-->>Investor: Stablecoin payout
```

### Forced Transfer (Regulatory Intervention)
#### Admin-initiated transfer that bypasses compliance and pause checks.

```mermaid
sequenceDiagram
    participant Admin
    participant AssetToken
    participant ComplianceModule

    Admin->>AssetToken: forceTransfer(from, to, trancheId, amount)
    Note over AssetToken: Requires DEFAULT_ADMIN_ROLE<br/>Calls super._update() directly<br/>Bypasses compliance hook & pause

    AssetToken->>AssetToken: Update balances via super._update()
    AssetToken->>AssetToken: Manually update balance checkpoints
    Note over AssetToken: Emits ForcedTransfer event
    Note over ComplianceModule: NOT called — intentional bypass
```

### Emergency Control – Freeze & Pause
#### Operational safety during incidents.

```mermaid
sequenceDiagram
    participant Admin
    participant ComplianceModule
    participant AssetToken

    Admin->>ComplianceModule: freeze(investor, true)
    Note over ComplianceModule: Emits InvestorFrozen event<br/>Investor cannot send or receive

    Admin->>AssetToken: pause()
    Note over AssetToken: All transfers blocked<br/>Exception: forceTransfer() still works

```

### Investor Data Query
#### Backend or frontend queries on-chain compliance data.

```mermaid
sequenceDiagram
    participant Backend
    participant ComplianceModule

    Backend->>ComplianceModule: getInvestor(address)
    ComplianceModule-->>Backend: (allowlisted, frozen, jurisdiction, investorType)
    Note over Backend: Used for UI display, reconciliation,<br/>and pre-flight transfer checks

```

---
