import DashboardPageLayout from "@/components/dashboard/layout";
import DashboardStat from "@/components/dashboard/stat";
import RebelsRanking from "@/components/dashboard/rebels-ranking";
import SecurityStatus from "@/components/dashboard/security-status";
import GearIcon from "@/components/icons/gear";
import ProcessorIcon from "@/components/icons/proccesor";
import BoomIcon from "@/components/icons/boom";
import mockDataJson from "@/../mock.json";
import { SidebarTrigger } from "@/components/ui/sidebar";
import type { MockData } from "@/types/dashboard";

const mockData = mockDataJson as MockData;

// Icon mapping
const iconMap = {
  gear: GearIcon,
  proccesor: ProcessorIcon,
  boom: BoomIcon,
};

export default function DashboardOverview() {
 
  
  return (
    <DashboardPageLayout
      header={{
        title: "Overview",
        description: "Last updated 12:05",
        icon: SidebarTrigger,
      }}
    >
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-6">
        {mockData.dashboardStats.map((stat, index) => (
          <DashboardStat
            key={index}
            label={stat.label}
            value={stat.value}
            description={stat.description}
            icon={iconMap[stat.icon as keyof typeof iconMap]}
            tag={stat.tag}
            intent={stat.intent}
            direction={stat.direction}
          />
        ))}
      </div>

  

      {/* Main 2-column grid section */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <RebelsRanking rebels={mockData.rebelsRanking} />
        <SecurityStatus statuses={mockData.securityStatus} />
      </div>

      
    </DashboardPageLayout>
  );
}
