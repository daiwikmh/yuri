import { http, createConfig } from 'wagmi';
import {  unichainSepolia } from "wagmi/chains";
import { metaMask } from '@wagmi/connectors';

export const wagmiConfig = createConfig({
  ssr: true, // Make sure to enable this for server-side rendering (SSR) applications.
  chains: [unichainSepolia],
  connectors: [
    metaMask({
      infuraAPIKey: import.meta.env.VITE_PUBLIC_INFURA_API_KEY,
    }),
  ],
  transports: {
    [unichainSepolia.id]: http(),
  }
});
