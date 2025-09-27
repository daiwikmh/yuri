import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { useState } from "react";

export function TopBar({ onAddNode }: { onAddNode: (type: string) => void }) {
  const [nodeType, setNodeType] = useState<string>("agent");

  return (
    <div className="flex items-center justify-between border-b bg-background p-2 shadow-sm">
      <div className="flex items-center gap-2">
        <Select value={nodeType} onValueChange={(val) => setNodeType(val)}>
          <SelectTrigger className="w-[200px]">
            <SelectValue placeholder="Select Node Type" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="agent">Agent Node</SelectItem>
            <SelectItem value="pool">Pool Node</SelectItem>
            <SelectItem value="poolwatcher">Pool Watcher Node</SelectItem>
            <SelectItem value="trigger">Trigger Node</SelectItem>
            <SelectItem value="start">Start Node</SelectItem>
            <SelectItem value="output">Output Node</SelectItem>
            <SelectItem value="test">Test Node</SelectItem>
            <SelectItem value="telegram_polling">Telegram Polling</SelectItem>
            <SelectItem value="webhook">Webhook</SelectItem>
                     
          </SelectContent>
        </Select>
        <Button onClick={() => onAddNode(nodeType)}>Add Node</Button>
      </div>
    </div>
  );
}
