import { Card, CardHeader } from "@/components/ui/card";
import { Handle, Position, type NodeProps, type Node, useReactFlow } from "@xyflow/react";
import { Trash2, Bot, Clock, CheckCircle, XCircle } from "lucide-react";
import type { ReactElement } from "react";

type AgentNodeData = Node<{
  label: string;
  status: "idle" | "running" | "success" | "error";
}>;


export function AgentNode({ data, id}: NodeProps<AgentNodeData>) {
  const { setNodes } = useReactFlow();
  const statusColor: Record<string, string> = {
    idle: "border-pink-300",
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

  return (
    <Card
      className={`relative w-[200px] shadow-md border ${statusColor[data.status || "idle"]}`}
    >
      <Handle type="target" position={Position.Left} />
      <CardHeader className="flex items-center justify-between p-4">
        <div className="flex items-center gap-2">
          <Bot className="w-6 h-6 text-blue-600" />
          <span className="text-lg font-semibold">{data.label}</span>
          {statusIcon[data.status || "idle"]}
        </div>
        <button
          onClick={() => setNodes((nodes) => nodes.filter((node) => node.id !== id))}
          className="w-8 h-8 flex items-center justify-center rounded-full hover:bg-red-100 transition-colors"
          title="Delete Node"
        >
          <Trash2 className="w-6 h-6 text-red-600" />
        </button>
      </CardHeader>
      <Handle type="source" position={Position.Right} />
    </Card>
  );
}
