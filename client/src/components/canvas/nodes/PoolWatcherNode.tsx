import { Card, CardHeader } from "@/components/ui/card";
import { Handle, Position, useReactFlow, type Node, type NodeProps } from "@xyflow/react";
import { Trash2, GlassesIcon, Clock, CheckCircle, XCircle } from "lucide-react";
import type { ReactElement } from "react";

type PoolWatcherNodeData = Node<{
  label: string;
  status: "idle" | "running" | "success" | "error";
}>;


export function PoolWatcherNode({ data, id }: NodeProps<PoolWatcherNodeData>) {
  const { setNodes } = useReactFlow();
  const statusColor:Record<string,string> = {
    idle: "border-blue-300",
    running: "border-yellow-400",
    monitoring: "border-yellow-500",
    success: "border-green-500",
    error: "border-red-500",
  };
  
  const statusIcon: Record<string, ReactElement> = {
    idle: <Clock className="w-3 h-3 text-gray-400" />,
    running: <Clock className="w-3 h-3 text-yellow-400 animate-spin" />,
    monitoring: <Clock className="w-3 h-3 text-yellow-500 animate-spin" />,
    success: <CheckCircle className="w-3 h-3 text-green-500" />,
    error: <XCircle className="w-3 h-3 text-red-500" />,
  };

  return (
    <Card
      className={`relative w-[250px] shadow-md border ${statusColor[data.status || "idle"]}`}
    >
      <Handle type="target" position={Position.Left} />
      <CardHeader className="flex items-center justify-between p-4">
        <div className="flex items-center gap-2">
          <GlassesIcon className="w-6 h-6 text-blue-600" />
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
