import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { createUserWallet } from "@/utils/wallet/CreateWallet";
import {
  Handle,
  Position,
  useReactFlow,
  type Node,
  type NodeProps,
} from "@xyflow/react";
import {
  CheckCircle,
  Clock,
  Copy,
  PlusCircle,
  Trash2,
  XCircle,
} from "lucide-react";
import { useState, type ReactElement } from "react";

type StartNodeData = Node<{
  label: string;
  status: "idle" | "running" | "success" | "error";
}>;

interface WalletInfo {
  userAddress: string;
  walletAddress: string;
}

export function StartNode({ data, id }: NodeProps<StartNodeData>) {
  const { setNodes } = useReactFlow();
  const [walletInfo, setWalletInfo] = useState<WalletInfo | null>(null);
  const [isCreating, setIsCreating] = useState(false);

  const statusColor: Record<string, string> = {
    idle: "border-green-300",
    running: "border-yellow-400",
    success: "border-green-500",
    error: "border-red-500",
  };

  const statusIcon: Record<string, ReactElement> = {
    idle: <Clock className="w-3 h-3 text-gray-400" />,
    running: <Clock className="w-3 h-3 text-yellow-400 animate-spin" />,
    success: <CheckCircle className="w-3 h-3 text-green-500" />,
    error: <XCircle className="w-3 h-3 text-red-500" />,
  };

  const handleCreateWallet = async () => {
    setIsCreating(true);
    try {
      const args = await createUserWallet();
      // The args should contain [userAddress, walletAddress] based on the smart contract event
      if (args && Array.isArray(args) && args.length >= 2) {
        setWalletInfo({
          userAddress: args[0],
          walletAddress: args[1],
        });
      }
    } catch (error) {
      console.error("Failed to create wallet:", error);
    } finally {
      setIsCreating(false);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  const truncateAddress = (address: string) => {
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  };

  return (
    <Card
      className={`relative w-[200px] shadow-md border ${statusColor[data.status || "idle"]}`}
    >
      <CardHeader className="flex justify-between items-center text-sm font-semibold">
        <span>{data.label}</span>
        {statusIcon[data.status || "idle"]}
        <button
          onClick={() =>
            setNodes((nodes) => nodes.filter((node) => node.id !== id))
          }
          className="w-8 h-8 m-auto flex items-center justify-center rounded-full hover:bg-red-100 transition-colors"
          title="Remove Node"
        >
          <Trash2 className="w-6 h-6 text-red-600" />
        </button>
        <button
          onClick={handleCreateWallet}
          disabled={isCreating}
          className="w-8 h-8 flex items-center justify-center rounded-full hover:bg-blue-100 transition-colors disabled:opacity-50"
          title="Create User Wallet"
        >
          {isCreating ? (
            <Clock className="w-4 h-4 text-blue-600 animate-spin" />
          ) : (
            <PlusCircle className="w-4 h-4 text-blue-600" />
          )}
        </button>
      </CardHeader>
      {walletInfo && (
        <CardContent className="pt-0 space-y-2">
          <div className="text-xs">
            <div className="flex items-center justify-between mb-1">
              <span className="text-gray-600">User Address:</span>
              <button
                onClick={() => copyToClipboard(walletInfo.userAddress)}
                className="p-1 hover:bg-gray-100 rounded"
                title="Copy user address"
              >
                <Copy className="w-3 h-3" />
              </button>
            </div>
            <div className="font-mono text-xs bg-gray-50 p-1 rounded border">
              {truncateAddress(walletInfo.userAddress)}
            </div>
          </div>

          <div className="text-xs">
            <div className="flex items-center justify-between mb-1">
              <span className="text-gray-600">Wallet Address:</span>
              <button
                onClick={() => copyToClipboard(walletInfo.walletAddress)}
                className="p-1 hover:bg-gray-100 rounded"
                title="Copy wallet address"
              >
                <Copy className="w-3 h-3" />
              </button>
            </div>
            <div className="font-mono text-xs bg-gray-50 p-1 rounded border">
              {truncateAddress(walletInfo.walletAddress)}
            </div>
          </div>
        </CardContent>
      )}
      <Handle type="source" position={Position.Right} />
    </Card>
  );
}
