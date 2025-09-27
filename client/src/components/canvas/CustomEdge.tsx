import { memo, type ReactNode } from "react";
 
import {
  BaseEdge,
  EdgeLabelRenderer,
  getBezierPath,
  useReactFlow,
  type EdgeProps,
} from "@xyflow/react";
import { X } from "lucide-react";
import { Button } from "../ui/button";
 
const ButtonEdgeIn = ({
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  style = {},
  markerEnd,
  children,
}: EdgeProps & { children: ReactNode }) => {
  const [edgePath, labelX, labelY] = getBezierPath({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
  });
 
  return (
    <>
      <BaseEdge path={edgePath} markerEnd={markerEnd} style={style} />
      <EdgeLabelRenderer>
        <div
          className="nodrag nopan pointer-events-auto absolute"
          style={{
            transform: `translate(-50%, -50%) translate(${labelX}px,${labelY}px)`,
          }}
        >
          {children}
        </div>
      </EdgeLabelRenderer>
    </>
  );
};

const ButtonEdge = memo((props: EdgeProps) => {
  
    const { setEdges } = useReactFlow();

  return (
    <ButtonEdgeIn {...props}>
      <Button size="icon" variant="secondary" onClick={() => setEdges((eds) =>
      eds.filter((e) => e.id !== props.id)
    )}>
        <X size={16} />
      </Button>
    </ButtonEdgeIn>
  );
});
 
export default ButtonEdge;