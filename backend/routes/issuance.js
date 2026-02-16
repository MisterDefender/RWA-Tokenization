const express = require("express");
const router = express.Router();

/**
 * POST /issuance/approve
 * Issuer approves a subscription after payment settlement
 */
router.post("/approve", async (req, res) => {
  const { investor, trancheId, amount } = req.body;

  // In reality:
  // - Verify payment settlement
  // - Call IssuanceModule.approveSubscription(...)
  res.json({
    message: "Subscription approved",
    investor,
    trancheId,
    amount
  });
});

module.exports = router;