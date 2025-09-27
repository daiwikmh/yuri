"use client";

import { apiPost, apiGet } from "@/lib/api";
import React, { useState } from "react";
import useSWR from "swr";
import PoolDataDisplay, { type PoolData } from "@/components/pool/poolsTable";
import { FeeAmount } from "@/lib/utils";

type Token = {
  chainId: number;
  address: string;
  decimals: number;
  symbol: string;
  name: string;
};

interface Pool {
  name: string;
  token0: Token;
  token1: Token;
  fee: number;
}

async function createPoolOnServer(pool: Pool) {
  const res = await apiPost("/pools", pool);
  console.log(res)
}

export default function Pool() {
  const [poolName, setPoolName] = useState("");
  const [token0, setToken0] = useState<Token>({
    chainId: 1,
    address: "",
    decimals: 18,
    symbol: "",
    name: "",
  });
  const [token1, setToken1] = useState<Token>({
    chainId: 1,
    address: "",
    decimals: 18,
    symbol: "",
    name: "",
  });
  const [fee, setFee] = useState<FeeAmount>(FeeAmount.MEDIUM);

  const { data, error, isLoading, mutate } = useSWR<PoolData[]>(
    "/pools",
    apiGet
  );

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    if (!poolName.trim()) {
      window.alert("Please enter a pool name");
      return;
    }
    if (!token0.symbol || !token1.symbol) {
      window.alert("Please fill out both tokens");
      return;
    }
    if (token0.address === token1.address) {
      window.alert("Token0 and Token1 cannot be the same");
      return;
    }

    const newPool = { name: poolName.trim(), token0, token1, fee };

    try {
      console.log("createPoolOnServer", newPool);
      await createPoolOnServer(newPool);
      console.log(" Pool stored on server");
      mutate();
    } catch {
      window.alert("Failed to save pool on server (check console)");
    }

    // reset form
    setPoolName("");
    setToken0({ chainId: 1, address: "", decimals: 18, symbol: "", name: "" });
    setToken1({ chainId: 1, address: "", decimals: 18, symbol: "", name: "" });
    setFee(3000);
  }

  function renderTokenForm(
    label: string,
    token: Token,
    setToken: (t: Token) => void
  ) {
    return (
      <div className="space-y-2">
        <h3 className="text-sm font-semibold">{label}</h3>
        <input
          placeholder="Symbol (e.g. USDC)"
          value={token.symbol}
          onChange={(e) => setToken({ ...token, symbol: e.target.value })}
          className="w-full p-2 rounded-md bg-muted border border-border"
        />
        <input
          placeholder="Name (e.g. USD Coin)"
          value={token.name}
          onChange={(e) => setToken({ ...token, name: e.target.value })}
          className="w-full p-2 rounded-md bg-muted border border-border"
        />
        <input
          placeholder="Address (0x...)"
          value={token.address}
          onChange={(e) => setToken({ ...token, address: e.target.value })}
          className="w-full p-2 rounded-md bg-muted border border-border"
        />
        <input
          type="number"
          placeholder="Decimals"
          value={token.decimals}
          onChange={(e) =>
            setToken({ ...token, decimals: parseInt(e.target.value) })
          }
          className="w-full p-2 rounded-md bg-muted border border-border"
        />
      </div>
    );
  }

  return (
    <div className="w-full h-full p-6 flex flex-col gap-6 font-roboto-mono">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-rebels tracking-widest">CREATE POOL</h1>
        <div className="text-sm text-muted-foreground">
          Create a blockchain pool (user provides tokens)
        </div>
      </div>

      {/* Form + Preview */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Form */}
        <form
          onSubmit={handleCreate}
          className="col-span-1 lg:col-span-2 bg-card rounded-xl border border-border p-6 shadow-lg space-y-6"
        >
          <h2 className="text-lg font-bold">Pool Details</h2>

          {/* Pool Name */}
          <div className="space-y-2">
            <label className="block text-sm">Pool Name</label>
            <input
              value={poolName}
              onChange={(e) => setPoolName(e.target.value)}
              placeholder="e.g. USDC-WETH"
              className="w-full p-2 rounded-md bg-muted border border-border"
            />
          </div>

          {/* Token0 + Token1 */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {renderTokenForm("Token0", token0, setToken0)}
            {renderTokenForm("Token1", token1, setToken1)}
          </div>

          {/* Fee */}
          <div className="space-y-2">
            <label className="block text-sm">Fee (bps)</label>
            <select
              value={fee}
              onChange={(e) => setFee(Number(e.target.value) as FeeAmount)}
              className="w-full p-2 rounded-md bg-muted border border-border"
            >
              {Object.entries(FeeAmount)
                .filter(([_k, v]) => typeof v === "number") // only enum values
                .map(([key, value]) => (
                  <option key={value} value={value}>
                    {key} ({value} bps)
                  </option>
                ))}
            </select>
          </div>

          {/* Buttons */}
          <div className="flex items-center gap-3">
            <button
              type="submit"
              className="px-4 py-2 bg-primary text-primary-foreground rounded-lg hover:opacity-90 transition"
            >
              Create Pool
            </button>
            <button
              type="button"
              onClick={() => {
                setPoolName("");
                setToken0({
                  chainId: 1,
                  address: "",
                  decimals: 18,
                  symbol: "",
                  name: "",
                });
                setToken1({
                  chainId: 1,
                  address: "",
                  decimals: 18,
                  symbol: "",
                  name: "",
                });
                setFee(3000);
              }}
              className="px-4 py-2 bg-muted rounded-lg border border-border"
            >
              Reset
            </button>
          </div>
        </form>

        {/* Preview */}
        <div className="bg-card rounded-xl border border-border p-6 shadow-lg">
          <h2 className="text-lg font-bold mb-3">Pool Preview</h2>
          <div>
            <div className="text-sm text-muted-foreground">Name</div>
            <div className="font-semibold">{poolName || "Unnamed Pool"}</div>

            <div className="mt-3 text-sm text-muted-foreground">Token0</div>
            <div className="font-mono">
              {token0.symbol || "?"} ({token0.name || "?"})
            </div>

            <div className="mt-3 text-sm text-muted-foreground">Token1</div>
            <div className="font-mono">
              {token1.symbol || "?"} ({token1.name || "?"})
            </div>

            <div className="mt-3 text-sm text-muted-foreground">Fee</div>
            <div className="font-mono">{fee} bps</div>
          </div>
        </div>
      </div>

      {/* Existing Pools */}
      <div className="bg-card rounded-xl border border-border p-6">
        <h2 className="text-lg font-bold mb-4">Your Pools</h2>
        {isLoading && <div>Loading...</div>}
        {error && <div className="text-red-500">Failed to load pools</div>}
        {data && <PoolDataDisplay pools={data} />}
      </div>
    </div>
  );
}
