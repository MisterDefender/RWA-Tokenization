const express = require("express");
const bodyParser = require("body-parser");

const investorRoutes = require("./routes/investors");
const issuanceRoutes = require("./routes/issuance");
const eventRoutes = require("./routes/events");

const app = express();
app.use(bodyParser.json());

app.use("/investors", investorRoutes);
app.use("/issuance", issuanceRoutes);
app.use("/events", eventRoutes);

app.get("/health", (_, res) => {
  res.json({ status: "ok" });
});

app.listen(3000, () => {
  console.log("Backend running on port 3000");
});