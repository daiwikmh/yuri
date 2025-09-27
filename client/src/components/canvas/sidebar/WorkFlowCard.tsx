import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { ScrollArea } from "@/components/ui/scroll-area"

interface WorkflowResultCardsProps {
  workflowResults: Record<string, any>
}

export function WorkflowResultCards({ workflowResults }: WorkflowResultCardsProps) {
  const entries = Object.entries(workflowResults)

  return (
    <div className="w-full h-full bg-sidebar-accent rounded-lg p-3">
      <ScrollArea className="h-full w-full">
        <div className="flex flex-col gap-3 pr-3">
          {entries.map(([key, value]) => (
            <Card
              key={key}
              className="bg-sidebar-bg border border-sidebar-border w-[280px] rounded-lg"
            >
              <CardHeader>
                <CardTitle className="text-sm font-medium text-sidebar-foreground">
                  Step {key}
                </CardTitle>
              </CardHeader>
              <CardContent className="text-xs text-sidebar-accent-foreground space-y-1">
                {value && typeof value === "object"
                  ? Object.entries(value).map(([field, fieldValue]) => (
                      <div key={field}>
                        <span className="font-medium">{field}:</span>{" "}
                        {typeof fieldValue === "object"
                          ? JSON.stringify(fieldValue, null, 2)
                          : String(fieldValue)}
                      </div>
                    ))
                  : String(value)}
              </CardContent>
            </Card>
          ))}
        </div>
      </ScrollArea>
    </div>
  )
}
