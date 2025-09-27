export const walletFactoryAbi = [
  {
    "inputs": [],
    "name": "createUserAccount",
    "outputs": [{ "internalType": "address payable", "name": "userWallet", "type": "address" }],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "address", "name": "user", "type": "address" },
      { "indexed": false, "internalType": "address", "name": "wallet", "type": "address" }
    ],
    "name": "AccountCreated",
    "type":"event"
  }
];