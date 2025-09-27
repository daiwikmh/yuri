import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Handle, Position, type NodeProps, type Node, useReactFlow } from "@xyflow/react";
import { Trash2, FileOutput, CheckCircle, XCircle, Clock } from "lucide-react";
import ReactMarkdown from 'react-markdown';
import type { ReactElement } from "react";

type OutputNodeData = Node<{
  label: string;
  status: "idle" | "running" | "success" | "error";
  result?: any;
  error?: string;
}>;

export function OutputNode({ data, id }: NodeProps<OutputNodeData>) {
  const { setNodes } = useReactFlow();

  const statusColor: Record<string, string> = {
    idle: "border-gray-300",
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

  // Extract the final meaningful result for markdown display
  const getFinalResult = () => {
    if (!data.result) return "No results yet";

    const result = data.result;

    // If it's workflow results, get the final meaningful content
    if (result.workflowResults && typeof result.workflowResults === 'object') {
      const workflowResults = result.workflowResults as Record<string, unknown>;
      const nodeIds = Object.keys(workflowResults);
      
      // Look for agent results first (most meaningful for display)
      for (const nodeId of nodeIds) {
        const nodeResult = workflowResults[nodeId];
        if (nodeResult && typeof nodeResult === 'object') {
          const nodeData = nodeResult as Record<string, unknown>;
          
          // Check for agent result
          if (nodeData.agentResult && typeof nodeData.agentResult === 'object') {
            const agentResult = nodeData.agentResult as Record<string, unknown>;
            if (agentResult.response || agentResult.answer || agentResult.content) {
              return agentResult.response || agentResult.answer || agentResult.content;
            }
          }
          
          // Check for direct response content
          if (nodeData.response || nodeData.answer || nodeData.content) {
            return nodeData.response || nodeData.answer || nodeData.content;
          }
        }
      }
      
      // Fallback to summary if available
      if (result.summary) {
        return result.summary;
      }
    }

    // For direct results (like from test nodes)
    if (typeof result === 'object') {
      const resultData = result as Record<string, unknown>;
      
      if (resultData.agentResult && typeof resultData.agentResult === 'object') {
        const agentResult = resultData.agentResult as Record<string, unknown>;
        if (agentResult.response || agentResult.answer || agentResult.content) {
          return agentResult.response || agentResult.answer || agentResult.content;
        }
      }
      
      if (resultData.response || resultData.answer || resultData.content) {
        return resultData.response || resultData.answer || resultData.content;
      }
    }

    return "Workflow completed successfully";
  };

  const finalResult = getFinalResult();

  return (
    <Card className={`relative w-[280px] shadow-md border ${statusColor[data.status || "idle"]}`}>
    <Handle type="target" position={Position.Left} />

      <CardHeader className="flex flex-row items-center justify-between p-3">
        <div className="flex items-center gap-2">
          <FileOutput className="w-4 h-4 text-purple-600" />
          <span className="text-sm font-semibold">{data.label}</span>
          {statusIcon[data.status || "idle"]}
        </div>
        <button
          onClick={(e) => {
            e.stopPropagation();
            setNodes((nodes) => nodes.filter((node) => node.id !== id));
          }}
          className="w-6 h-6 flex items-center justify-center rounded-full hover:bg-red-100 transition-colors"
          title="Delete Node"
        >
          <Trash2 className="w-3 h-3 text-red-600" />
        </button>
      </CardHeader>

      <CardContent className="p-3 pt-0">
        {data.status === "error" && data.error ? (
          <div className="text-red-500 text-xs">
            <div className="font-medium mb-1">Error:</div>
            <div className="text-red-400">{data.error}</div>
          </div>
        ) : (
          <ScrollArea className="h-32 w-full">
            <div className="pr-4 ">
              <ReactMarkdown
                components={{
                  p: ({ children }) => (
                    <p className="text-white text-xs leading-relaxed mb-2 last:mb-0">
                      {children}
                    </p>
                  ),
                  h1: ({ children }) => (
                    <h1 className="text-white text-sm font-bold mb-2">
                      {children}
                    </h1>
                  ),
                  h2: ({ children }) => (
                    <h2 className="text-white text-xs font-semibold mb-2">
                      {children}
                    </h2>
                  ),
                  h3: ({ children }) => (
                    <h3 className="text-white text-xs font-medium mb-1">
                      {children}
                    </h3>
                  ),
                  code: ({ children, className }) => {
                    const isBlock = className?.includes('language-');
                    return isBlock ? (
                      <pre className="bg-gray-100 p-2 rounded text-[10px] overflow-x-auto mb-2">
                        <code className="text-gray-800">{children}</code>
                      </pre>
                    ) : (
                      <code className="bg-gray-100 px-1 py-0.5 rounded text-[10px] text-gray-800">
                        {children}
                      </code>
                    );
                  },
                  ul: ({ children }) => (
                    <ul className="text-white text-xs space-y-0.5 ml-3 list-disc mb-2">
                      {children}
                    </ul>
                  ),
                  ol: ({ children }) => (
                    <ol className="text-white text-xs space-y-0.5 ml-3 list-decimal mb-2">
                      {children}
                    </ol>
                  ),
                  li: ({ children }) => (
                    <li className="text-white">{children}</li>
                  ),
                  blockquote: ({ children }) => (
                    <blockquote className="border-l-2 border-gray-300 pl-2 text-gray-600 italic mb-2">
                      {children}
                    </blockquote>
                  ),
                  strong: ({ children }) => (
                    <strong className="font-semibold text-white">{children}</strong>
                  ),
                  em: ({ children }) => (
                    <em className="italic text-gray-700">{children}</em>
                  ),
                }}
              >
                {String(finalResult)}
              </ReactMarkdown>
            </div>
          </ScrollArea>
        )}
      </CardContent>
    </Card>
  );
}
