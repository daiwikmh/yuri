import React from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";


export interface PoolData {
  name: string;
  poolAddress: string;
  sqrtPriceX96: string;
  tick: number;
  liquidity: string;
  observationIndex: number;
  feeProtocol: number;
}

interface Props {
  pools: PoolData[] | undefined;
}

const PoolDataDisplay: React.FC<Props> = ({ pools }) => {
  return (
    <Card className="bg-card text-card-foreground border border-border">
      <CardHeader>
        <CardTitle className="text-lg font-bold">Liquidity Pools</CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Pool Address</TableHead>
              <TableHead>Price</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {pools?.map((pool, index) => (
              <TableRow key={index}>
                <TableCell className="font-medium">{pool.name}</TableCell>
                <TableCell className="truncate max-w-[200px]">
                  <a
                    href={`https://etherscan.io/address/${pool.poolAddress}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-blue-500 hover:underline"
                  >
                    {pool.poolAddress}
                  </a>
                </TableCell>
                <TableCell>{pool.sqrtPriceX96}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
};

export default PoolDataDisplay;