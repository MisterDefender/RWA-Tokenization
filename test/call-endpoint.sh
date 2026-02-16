curl http://localhost:3000/health
curl -X POST http://localhost:3000/investors/onboard \
  -H "Content-Type: application/json" \
  -d '{"wallet":"0x123","jurisdiction":1,"investorType":"ACCREDITED"}'
