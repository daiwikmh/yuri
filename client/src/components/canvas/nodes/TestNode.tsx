import { Card, CardHeader } from "@/components/ui/card";
import { Handle, Position, type NodeProps, type Node, useReactFlow } from "@xyflow/react";
import { Trash2, TestTube, Clock, CheckCircle, XCircle } from "lucide-react";
import { Modal } from "./ui/TestModal";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import type { ReactElement } from "react";
import { useState } from "react";

type TestNodeData = Node<{
  label: string;
  status: "idle" | "running" | "success" | "error";
  question?: string;
  onExecuteTest?: (nodeId: string, question: string) => void;
}>;

export function TestNode({ data, id }: NodeProps<TestNodeData>) {
  const { setNodes } = useReactFlow();
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [question, setQuestion] = useState(data.question || "");
  
  const statusColor: Record<string, string> = {
    idle: "border-purple-300",
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

  const handleCardClick = () => {
    setIsModalOpen(true);
  };

  const handleExecuteTest = () => {
    if (question.trim() && data.onExecuteTest) {
      data.onExecuteTest(id, question.trim());
      setIsModalOpen(false);
    }
  };

  const handleSaveQuestion = () => {
    // Update the node data with the question
    setNodes((nodes) =>
      nodes.map((node) =>
        node.id === id
          ? {
              ...node,
              data: {
                ...node.data,
                question: question.trim(),
              },
            }
          : node
      )
    );
    setIsModalOpen(false);
  };

  return (
    <>
      <Card
        className={`relative w-[200px] shadow-md border ${statusColor[data.status || "idle"]} cursor-pointer hover:shadow-lg transition-shadow`}
        onClick={handleCardClick}
      >
        <Handle type="target" position={Position.Left} />
        <CardHeader className="flex items-center justify-between p-4">
          <div className="flex items-center gap-2">
            <TestTube className="w-6 h-6 text-purple-600" />
            <div className="flex flex-col">
              <span className="text-lg font-semibold">{data.label}</span>
              {data.question ? (
                <span className="text-xs text-purple-600 font-medium truncate max-w-[120px]">
                  "{data.question}"
                </span>
              ) : (
                <span className="text-xs text-gray-400">
                  Click to set question
                </span>
              )}
            </div>
            {statusIcon[data.status || "idle"]}
          </div>
          <button
            onClick={(e) => {
              e.stopPropagation(); // Prevent triggering the card click
              setNodes((nodes) => nodes.filter((node) => node.id !== id));
            }}
            className="w-8 h-8 flex items-center justify-center rounded-full hover:bg-red-100 transition-colors"
            title="Delete Node"
          >
            <Trash2 className="w-4 h-4 text-red-600" />
          </button>
        </CardHeader>
        <Handle type="source" position={Position.Right} />
      </Card>

      <Modal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        title="Test Agent"
      >
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Question for Agent:
            </label>
            <Input
              value={question}
              onChange={(e) => setQuestion(e.target.value)}
              placeholder="Enter your question to test the agent..."
              className="w-full text-black"
              onKeyDown={(e) => {
                if (e.key === 'Enter' && question.trim()) {
                  handleExecuteTest();
                }
              }}
            />
          </div>
          
          <div className="flex gap-2 pt-4">
            <Button 
              onClick={handleSaveQuestion}
              variant="default"
              disabled={!question.trim()}
            >
              Save Only
            </Button>
            <Button 
              onClick={() => setIsModalOpen(false)}
              variant="secondary"
            >
              Cancel
            </Button>
          </div>
        </div>
      </Modal>
    </>
  );
}
