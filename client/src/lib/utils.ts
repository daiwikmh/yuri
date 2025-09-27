import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export enum FeeAmount {
  LOWEST = 100,
  LOW_200 = 200,
  LOW_300 = 300,
  LOW_400 = 400,
  LOW = 500,
  MEDIUM = 3000,
  HIGH = 10000,
}