const express = require("express");
const router = express.Router();

/**
 * POST /investors/onboard
 * Called after KYC completion
 */
router.post("/onboard", async (req, res) => {
  const { wallet, jurisdiction, investorType } = req.body;

  // In reality: verify KYC provider reference
  // Then call ComplianceModule.setInvestor(...)
  res.json({
    message: "Investor onboarded (off-chain)",
    wallet,
    jurisdiction,
    investorType
  });
});

module.exports = router;