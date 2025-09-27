import { AppLayout } from "@/pages/Layout";
import DashboardOverview from "./pages/DashBoard";
import "./App.css";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {  WagmiProvider } from "wagmi";
import { wagmiConfig } from "@/utils/wallet/config/WalletConfig";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import Pool from "@/components/pool/Pool";
import Canvas from "./pages/Canvas";
function App() {
  const client = new QueryClient();
  
  return (
    <>
      <WagmiProvider config={wagmiConfig}>
        <QueryClientProvider client={client}>
          <BrowserRouter>
            <AppLayout>
              <Routes>
                <Route path="/" element={<DashboardOverview />} />
                <Route path="/create-pool" element={<Pool />} />
                <Route path="/canvas" element={<Canvas />} />
              </Routes>
            </AppLayout>
          </BrowserRouter>
        </QueryClientProvider>
      </WagmiProvider>
    </>
  );
}

export default App;
