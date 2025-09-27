import { agentApiPost } from "./api";

// Enhanced nodeFunctions.ts
export const nodeFunctions: Record<string, (input: any, params?: any) => any | Promise<any>> = {
  start: () => ({ 
    message: "Workflow started",
    timestamp: new Date().toISOString()
  }),
  
  trigger: (input) => ({ 
    triggered: true,
    triggerData: input || "Manual trigger",
    timestamp: new Date().toISOString()
  }),
  
  agent: async (input) => {
     try {
       // Make POST request to the agent query endpoint
       const response = await agentApiPost<any>({
         question: input?.inputData?.question || input || "Default query"
       });
       
       return {
         agentResult: response,
         processedInput: input,
         success: true,
         timestamp: new Date().toISOString()
       };
     } catch (error) {
       console.error('Agent API request failed:', error);
       return {
         agentResult: null,
         processedInput: input,
         success: false,
         error: error instanceof Error ? error.message : 'Unknown error',
         timestamp: new Date().toISOString()
       };
     }
   },
  
  pool: (input) => {
    return { 
      poolData: input,
      poolStatus: "stored",
      poolId: Math.random().toString(36).substr(2, 9),
      timestamp: new Date().toISOString()
    };
  },
  
  poolwatcher: async (input) => {
    // Simulate pool watching
    await new Promise(resolve => setTimeout(resolve, 800));
    return {
      watchStatus: "monitoring",
      poolChanges: Math.floor(Math.random() * 10),
      lastUpdate: new Date().toISOString(),
      inputData: input
    };
  },
  test: (input: unknown) => {
     // Simple test function that just passes the input through
     return {
       testResult: "Test node executed successfully",
       inputData: input,
       timestamp: new Date().toISOString(),
       // Pass the input data to the next node
       ...(input && typeof input === 'object' ? input as Record<string, unknown> : {})
     };
   },
  
  output: (input) => {
    return {
      finalResult: input,
      outputGenerated: true,
      timestamp: new Date().toISOString()
    };
  }
};
