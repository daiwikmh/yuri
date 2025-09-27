"use client";

import { writeContract, waitForTransactionReceipt } from "@wagmi/core";
import { wagmiConfig } from "./config/WalletConfig";
import { walletFactoryAbi } from "./abi/WalletFactory";
import { decodeEventLog } from "viem";

const walletFactoryAddress = "0xc2E0624b87B4d71e38a5633693770f202c806B85";

export async function createUserWallet() {
  try {
    // 1. Send transaction via wagmi
    const txHash = await writeContract(wagmiConfig, {
      address: walletFactoryAddress,
      abi: walletFactoryAbi,
      functionName: "createUserAccount",
      args: [],
    });

    console.log("Transaction hash:", txHash);

    // 2. Wait for confirmation
    const receipt = await waitForTransactionReceipt(wagmiConfig, { hash: txHash });
    console.log("Receipt:", receipt);

    // 3. Find and decode the AccountCreated event
    const log = receipt.logs.find(
      (l) => l.address.toLowerCase() === walletFactoryAddress.toLowerCase()
    );

    if (!log) throw new Error("No AccountCreated event found");

    const decoded = decodeEventLog({
      abi: walletFactoryAbi,
      data: log.data,
      topics: log.topics,
    });

    console.log("Decoded AccountCreated event:", decoded);

    alert(`Wallet created: ${decoded.args}`);
    return decoded.args;
  } catch (error: any) {
    console.error("Error creating wallet:", error);
    alert("Failed: " + error.message);
    throw error;
  }
}