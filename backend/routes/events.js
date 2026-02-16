const express = require("express");
const router = express.Router();

/**
 * GET /events
 * Indexed on-chain events for audit / statements
 */
router.get("/", async (_, res) => {
  // In reality: query indexed Transfer/Mint/Burn events
  res.json({
    events: [],
    note: "Events derived from on-chain logs"
  });
});

module.exports = router;