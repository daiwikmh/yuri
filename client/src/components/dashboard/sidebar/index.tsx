"use client";

import * as React from "react";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import AtomIcon from "@/components/icons/atom";
import BracketsIcon from "@/components/icons/brackets";
import ProcessorIcon from "@/components/icons/proccesor";
import CuteRobotIcon from "@/components/icons/cute-robot";
import EmailIcon from "@/components/icons/email";
import GearIcon from "@/components/icons/gear";
import MonkeyIcon from "@/components/icons/monkey";
import DotsVerticalIcon from "@/components/icons/dots-vertical";
import { Bullet } from "@/components/ui/bullet";
import LockIcon from "@/components/icons/lock";

import { useAccount, useConnect, useDisconnect } from "wagmi";

type DashboardSidebarProps = React.ComponentProps<typeof Sidebar> & {
  /**
   * Optional: parent can pass this to handle navigation (e.g. react-router's navigate or Next.js router).
   * If not provided, the component will attempt a history.pushState fallback.
   */
  onNavigate?: (url: string) => void;
  /** Optional initial active path override */
  initialActive?: string;
};

const navItems = [
  { title: "Overview", url: "/", icon: BracketsIcon, locked: false },
  { title: "Create Pool", url: "/create-pool", icon: AtomIcon, locked: false },
  { title: "Canvas", url: "/canvas", icon: ProcessorIcon, locked: false },
  { title: "Security", url: "/security", icon: CuteRobotIcon, locked: false },
  { title: "Communication", url: "/communication", icon: EmailIcon, locked: false },
  { title: "Admin Settings", url: "/admin", icon: GearIcon, locked: true },
];

function shortenAddress(addr: string) {
  if (!addr) return "";
  return addr.slice(0, 6) + "..." + addr.slice(-4);
}

export function DashboardSidebar({
  className,
  onNavigate,
  initialActive,
  ...props
}: DashboardSidebarProps) {
  const { address } = useAccount();
  const { connectors, connect } = useConnect();
  const { disconnect } = useDisconnect();

  // Initialize from initialActive prop or current location
  const [activeUrl, setActiveUrl] = React.useState<string>(() => {
    try {
      return initialActive ?? (typeof window !== "undefined" ? window.location.pathname : "/");
    } catch {
      return initialActive ?? "/";
    }
  });

  // Keep in sync with browser navigation (back/forward)
  React.useEffect(() => {
    const onPop = () => {
      setActiveUrl(window.location.pathname);
    };
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  // Centralized click handler
  function handleNavClick(url: string) {
    // update active state visually first
    setActiveUrl(url);

    // If parent gave us a navigation function (recommended for apps using a router), call it
    if (typeof onNavigate === "function") {
      try {
        onNavigate(url);
        return;
      } catch {
        // fallthrough to history fallback
      }
    }

    // Fallback: try history.pushState so page doesn't fully reload
    try {
      if (window.location.pathname !== url) {
        window.history.pushState({}, "", url);
        // dispatch popstate so any listeners (including the app) can react
        window.dispatchEvent(new PopStateEvent("popstate"));
      }
      return;
    } catch {
      // last resort: full navigation
      window.location.assign(url);
    }
  }

  return (
    <Sidebar {...props} className={cn(className)}>
      <SidebarHeader className="rounded-t-lg flex gap-3 flex-row rounded-b-none">
        <div className="flex overflow-clip size-12 shrink-0 items-center justify-center rounded bg-sidebar-primary-foreground/10 transition-colors group-hover:bg-sidebar-primary text-sidebar-primary-foreground">
          <MonkeyIcon className="size-10 group-hover:scale-[1.7] origin-top-left transition-transform" />
        </div>
        <div className="grid flex-1 text-left text-sm leading-tight">
          <span className="text-2xl font-display">Y.U.R.I.</span>
          <span className="text-xs uppercase">Leverage on ETH</span>
        </div>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup className="rounded-t-none">
          <SidebarGroupLabel>
            <Bullet className="mr-2" />
            Tools
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {navItems.map((item) => {
                const isActive = item.url === activeUrl;
                return (
                  <SidebarMenuItem
                    key={item.title}
                    className={cn(item.locked && "pointer-events-none opacity-50")}
                    data-disabled={item.locked}
                  >
                    <SidebarMenuButton
                      // we don't use asChild or anchor navigation here: handle clicks ourselves
                      isActive={isActive}
                      disabled={item.locked}
                      onClick={() => !item.locked && handleNavClick(item.url)}
                      className={cn(
                        "disabled:cursor-not-allowed w-full text-left",
                        item.locked && "pointer-events-none"
                      )}
                    >
                      <div className="flex items-center gap-3 w-full">
                        <item.icon className="size-5" />
                        <span>{item.title}</span>
                      </div>
                    </SidebarMenuButton>

                    {item.locked && (
                      <SidebarMenuBadge>
                        <LockIcon className="size-5 block" />
                      </SidebarMenuBadge>
                    )}
                  </SidebarMenuItem>
                );
              })}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="p-0 ">
        <SidebarGroup>
          <SidebarGroupLabel>
            <Bullet className="mr-2" />
            User
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              <SidebarMenuItem>
                {!address ? (
                  <div className="flex flex-col gap-2 px-3 py-2">
                    {connectors.map((connector) => (
                      <button
                        key={connector.uid}
                        onClick={() => connect({ connector })}
                        className="w-full px-4 py-2 rounded-md bg-sidebar-primary text-sidebar-primary-foreground hover:bg-sidebar-primary/80"
                      >
                        Connect {connector.name}
                      </button>
                    ))}
                  </div>
                ) : (
                  <Popover>
                    <PopoverTrigger className="flex gap-0.5 w-full group cursor-pointer">
                      <div className="shrink-0 flex size-14 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground overflow-clip">
                        <MonkeyIcon className="size-8" />
                      </div>
                      <div className="group/item pl-3 pr-1.5 pt-2 pb-1.5 flex-1 flex bg-sidebar-accent hover:bg-sidebar-accent-active/75 items-center rounded group-data-[state=open]:bg-sidebar-accent-active group-data-[state=open]:hover:bg-sidebar-accent-active group-data-[state=open]:text-sidebar-accent-foreground">
                        <div className="grid flex-1 text-left text-sm leading-tight">
                          <span className="truncate text-xl font-display">
                            {shortenAddress(address as string)}
                          </span>
                          <span className="truncate text-xs uppercase opacity-50 group-hover/item:opacity-100">
                            Connected
                          </span>
                        </div>
                        <DotsVerticalIcon className="ml-auto size-4" />
                      </div>
                    </PopoverTrigger>
                    <PopoverContent
                      className="w-56 p-0"
                      side="bottom"
                      align="end"
                      sideOffset={4}
                    >
                      <div className="flex flex-col">
                        <button
                          onClick={() => disconnect()}
                          className="flex items-center px-4 py-2 text-sm hover:bg-accent"
                        >
                          <GearIcon className="mr-2 h-4 w-4" />
                          Disconnect
                        </button>
                      </div>
                    </PopoverContent>
                  </Popover>
                )}
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarFooter>
    </Sidebar>
  );
}
