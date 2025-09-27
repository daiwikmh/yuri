import { ChevronDown, ChevronRight, Play, Square } from "lucide-react";
import { useState } from "react";
import { WorkflowResultCards } from "./WorkFlowCard";

interface WorkflowSidebarProps {
  isWorkflowRunning: boolean;
  workflowResults: Record<string, unknown>;
  onRunWorkflow: () => void;
}

export function WorkflowSidebar({
  isWorkflowRunning,
  workflowResults,
  onRunWorkflow,
}: WorkflowSidebarProps) {
  const [isResultsExpanded, setIsResultsExpanded] = useState(false);
  const executedNodesCount = Object.keys(workflowResults).length;

  return (
    <div className="w-[300px] h-screen bg-sidebar border-r border-sidebar-border flex flex-col">
      {/* Header */}
      <div className="p-4 border-b border-sidebar-border">
        <h2 className="text-lg font-semibold text-sidebar-foreground mb-4">
          Workflow Control
        </h2>

        {/* Run Button */}
        <button
          onClick={onRunWorkflow}
          disabled={isWorkflowRunning}
          className="w-full flex items-center justify-center gap-2 px-4 py-2 bg-sidebar-primary text-sidebar-primary-foreground rounded-lg hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed transition-opacity"
        >
          {isWorkflowRunning ? (
            <>
              <Square className="w-4 h-4" />
              Running...
            </>
          ) : (
            <>
              <Play className="w-4 h-4" />
              Run Workflow
            </>
          )}
        </button>
      </div>

      {/* Status Section */}
      <div className="p-4 border-b border-sidebar-border">
        <h3 className="text-sm font-medium text-sidebar-foreground mb-3">
          Status
        </h3>

        <div className="space-y-2 text-sm">
          <div className="flex justify-between items-center">
            <span className="text-sidebar-foreground/70">Running:</span>
            <span
              className={`px-2 py-1 rounded text-xs font-medium ${
                isWorkflowRunning
                  ? "bg-warning/20 text-warning"
                  : "bg-success/20 text-success"
              }`}
            >
              {isWorkflowRunning ? "Yes" : "No"}
            </span>
          </div>

          <div className="flex justify-between items-center">
            <span className="text-sidebar-foreground/70">Executed Nodes:</span>
            <span className="text-sidebar-foreground font-medium">
              {executedNodesCount}
            </span>
          </div>
        </div>
      </div>

      {/* Results Section */}
      <div className="flex-1 p-4 overflow-hidden">
        <div className="flex items-center justify-between mb-3 ">
          <h3 className="text-sm font-medium text-sidebar-foreground">
            Results
          </h3>

          {executedNodesCount > 0 && (
            <button
              onClick={() => setIsResultsExpanded(!isResultsExpanded)}
              className="flex items-center gap-1 text-xs text-sidebar-foreground/70 hover:text-sidebar-foreground transition-colors"
            >
              {isResultsExpanded ? (
                <>
                  <ChevronDown className="w-3 h-3" />
                  Hide
                </>
              ) : (
                <>
                  <ChevronRight className="w-3 h-3" />
                  Show
                </>
              )}
            </button>
          )}
        </div>

        {executedNodesCount === 0 ? (
          <div className="text-xs text-sidebar-foreground/50 italic">
            No results yet. Run the workflow to see results.
          </div>
        ) : isResultsExpanded ? (
            <WorkflowResultCards workflowResults={workflowResults} />
        ) : (
          <div className="text-xs text-sidebar-foreground/70">
            {executedNodesCount} node{executedNodesCount !== 1 ? "s" : ""}{" "}
            executed. Click "Show" to view details.
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="p-4 border-t border-sidebar-border">
        <div className="text-xs text-sidebar-foreground/50 text-center">
          Workflow Execution Panel
        </div>
      </div>
    </div>
  );
}
