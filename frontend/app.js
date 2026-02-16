let signer;

async function connectWallet() {
  if (!window.ethereum) {
    alert("MetaMask required");
    return;
  }

  const provider = new ethers.BrowserProvider(window.ethereum);
  signer = await provider.getSigner();
  alert("Connected: " + await signer.getAddress());
}

async function requestSubscription() {
  alert("Subscription request sent (on-chain via IssuanceModule)");
}

async function transfer() {
  alert("Transfer triggered (ERC-1155 safeTransferFrom)");
}

async function claimDividend() {
  alert("Dividend claim triggered");
}

document.getElementById("connect").onclick = connectWallet;