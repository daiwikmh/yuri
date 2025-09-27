import { useCallback, useState } from "react";

import {
  ReactFlow,
  addEdge,
  Controls,
  Background,
  type Node,
  type Edge,
  type FitViewOptions,
  type OnConnect,
  type DefaultEdgeOptions,
  BackgroundVariant,
  MiniMap,
  ReactFlowProvider,
  useNodesState,
  useEdgesState,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import { AgentNode } from "@/components/canvas/nodes/AgentNode";
import { TopBar } from "@/components/canvas/topbar/TopBar";
import { PoolWatcherNode } from "@/components/canvas/nodes/PoolWatcherNode";
import { PoolNode } from "@/components/canvas/nodes/PoolNode";
import { StartNode } from "@/components/canvas/nodes/StartNode";
import { TriggerNode } from "@/components/canvas/nodes/TriggerNode";
import { OutputNode } from "@/components/canvas/nodes/OutputNode";
import { TestNode } from "@/components/canvas/nodes/TestNode";
import { nodeFunctions } from "@/lib/nodeFunction";
import ButtonEdge from "@/components/canvas/CustomEdge";
import { WorkflowSidebar } from "@/components/canvas/sidebar/WorkflowSidebar";
import { v4 as uuid } from "uuid";


// Types for workflow execution
type NodeStatus = "idle" | "running" | "success" | "error";

const nodeType = {
  agent: AgentNode,
  poolwatcher: PoolWatcherNode,
  pool: PoolNode,
  start: StartNode,
  trigger: TriggerNode,
  output: OutputNode,
  test: TestNode,
};

const initialNodes: Node[] = [];
const initialEdges: Edge[] = [];
const edgeTypes = { buttonedge: ButtonEdge };
const fitViewOptions: FitViewOptions = { padding: 0.2 };
const defaultEdgeOptions: DefaultEdgeOptions = { animated: true };

let id = 0;

export default function Canvas() {
  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
    const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);
    const [workflowResults, setWorkflowResults] = useState<Record<string, unknown>>({});
    const [isWorkflowRunning, setIsWorkflowRunning] = useState(false);
    
    const addNode = (type: string) => {
        const baseData = {
          label: `${type.charAt(0).toUpperCase() + type.slice(1)} Node`,
          status: "idle" as NodeStatus,
          result: null,
          error: null,
        };
    
        const newNode: Node = {
          id: `${id++}`,
          type,
          position: { x: Math.random() * 400 + 100, y: Math.random() * 200 + 100 },
          data: baseData,
        };
        
        setNodes((nds) => [...nds, newNode]);
      };
  const onConnect: OnConnect = useCallback(
    (connection) => {
      const edge: Edge = { ...connection, type: "buttonedge", id: uuid() };
      setEdges((eds) => addEdge(edge, eds));
    },
    [setEdges],
  );

  // Update node status and result
  const updateNodeStatus = useCallback(
    (nodeId: string, status: NodeStatus, result?: unknown, error?: string) => {
      setNodes((prevNodes) =>
        prevNodes.map((node) => {
          if (node.id === nodeId) {
            return {
              ...node,
              data: {
                ...node.data,
                status,
                result,
                error,
              },
            };
          }
          return node;
        }),
      );
    },
    [setNodes],
  );

  // Find connected nodes
  const getConnectedNodes = useCallback(
    (nodeId: string, direction: "incoming" | "outgoing") => {
      return edges
        .filter((edge) =>
          direction === "incoming"
            ? edge.target === nodeId
            : edge.source === nodeId,
        )
        .map((edge) => (direction === "incoming" ? edge.source : edge.target));
    },
    [edges],
  );

  // Execute a single node
  const executeNode = useCallback(
    async (node: Node, inputData: unknown = null): Promise<unknown> => {
      try {
        updateNodeStatus(node.id, "running");

        // Get the function for this node type
        const nodeFunction = nodeFunctions[node.type || ""];
        if (!nodeFunction) {
          throw new Error(`No function defined for node type: ${node.type}`);
        }

        // For test nodes, use the configured question
        let actualInput = inputData;
        if (node.type === "test" && node.data.question) {
          actualInput = { question: node.data.question };
        }

        // Execute the function
        const result = await nodeFunction(actualInput, node.data);


        // Update node with success status and result
        updateNodeStatus(node.id, "success", result);

        return result;
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : "Unknown error";
        updateNodeStatus(node.id, "error", null, errorMessage);
        throw error;
      }
    },
    [updateNodeStatus],
  );

  // Execute workflow in topological order
  const runWorkflow = useCallback(async () => {
    if (isWorkflowRunning) return;

    setIsWorkflowRunning(true);
    setWorkflowResults({});

    try {
      // Reset all nodes to idle status
      setNodes((prevNodes) =>
        prevNodes.map((node) => ({
          ...node,
          data: {
            ...node.data,
            status: "idle" as NodeStatus,
            result: null,
            error: undefined,
          },
        })),
      );

      // Find start nodes (nodes with no incoming edges)
      const startNodes = nodes.filter(
        (node) =>
          !edges.some((edge) => edge.target === node.id) ||
          node.type === "start",
      );

      if (startNodes.length === 0) {
        throw new Error(
          "No start nodes found. Add a Start node to begin the workflow.",
        );
      }

      // Track results for passing between nodes
      const nodeResults: Record<string, unknown> = {};
      const executedNodes = new Set<string>();
      const executionQueue = [...startNodes];

      // Process nodes in execution order
      while (executionQueue.length > 0) {
        const currentNode = executionQueue.shift()!;

        if (executedNodes.has(currentNode.id)) continue;

        // Check if all prerequisite nodes have been executed
        const incomingNodeIds = getConnectedNodes(currentNode.id, "incoming");
        const prerequisitesMet = incomingNodeIds.every((nodeId) =>
          executedNodes.has(nodeId),
        );

        if (!prerequisitesMet) {
          // Move to end of queue and try later
          executionQueue.push(currentNode);
          continue;
        }

        // Gather input data from connected nodes
        let inputData: unknown = null;
        if (incomingNodeIds.length > 0) {
          inputData = incomingNodeIds.reduce(
            (acc, nodeId) => {
              const nodeResult = nodeResults[nodeId];
              if (
                typeof acc === "object" &&
                acc !== null &&
                typeof nodeResult === "object" &&
                nodeResult !== null
              ) {
                return { ...acc, ...(nodeResult as Record<string, unknown>) };
              }
              return acc;
            },
            {} as Record<string, unknown>,
          );
        }

        try {
          // Execute the node
          const result = await executeNode(currentNode, inputData);
          nodeResults[currentNode.id] = result;
          executedNodes.add(currentNode.id);

          // Add connected output nodes to execution queue
          const outgoingNodeIds = getConnectedNodes(currentNode.id, "outgoing");
          const nextNodes = nodes.filter(
            (node) =>
              outgoingNodeIds.includes(node.id) && !executedNodes.has(node.id),
          );
          executionQueue.push(...nextNodes);
        } catch (error) {
          console.error(`Error executing node ${currentNode.id}:`, error);
          // Continue with other nodes even if one fails
        }

        // Add small delay to show the execution flow
        await new Promise((resolve) => setTimeout(resolve, 500));
      }

      // Update Output nodes with all results
      const outputNodes = nodes.filter((node) => node.type === "output");
      outputNodes.forEach((outputNode) => {
        updateNodeStatus(outputNode.id, "success", {
          workflowResults: nodeResults,
          executedNodes: Array.from(executedNodes),
          summary: `Workflow completed. Executed ${executedNodes.size} nodes.`,
        });
      });

      setWorkflowResults(nodeResults);
    } catch (error) {
      console.error("Workflow execution failed:", error);
      // Update all Output nodes with error
      const outputNodes = nodes.filter((node) => node.type === "output");
      outputNodes.forEach((outputNode) => {
        updateNodeStatus(
          outputNode.id,
          "error",
          null,
          error instanceof Error ? error.message : "Workflow execution failed",
        );
      });
    } finally {
      setIsWorkflowRunning(false);
    }
  }, [
    nodes,
    edges,
    executeNode,
    updateNodeStatus,
    getConnectedNodes,
    isWorkflowRunning,
    setNodes,
  ]);


  return (
    <ReactFlowProvider>
      <div className="w-full h-full rounded-lg flex">
        

        <div className="flex-1 flex flex-col">
          <TopBar onAddNode={addNode} />

          <ReactFlow
            nodes={nodes}
            nodeTypes={nodeType}
            edgeTypes={edgeTypes}
            edges={edges}
            colorMode="dark"
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onConnect={onConnect}
            fitView
            fitViewOptions={fitViewOptions}
            defaultEdgeOptions={defaultEdgeOptions}
          >
            <Background
              variant={BackgroundVariant.Dots}
              gap={20}
              color="#ccc"
            />
            <MiniMap />
            <Controls />
          </ReactFlow>
        </div>
        <WorkflowSidebar
          isWorkflowRunning={isWorkflowRunning}
          workflowResults={workflowResults}
          onRunWorkflow={runWorkflow}
        />
      </div>
    </ReactFlowProvider>
  );
}