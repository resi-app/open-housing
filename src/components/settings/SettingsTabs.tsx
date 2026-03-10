"use client";

import { useTranslations } from "next-intl";

export type SettingsTab = "building" | "entrances" | "flats" | "voting" | "connections";

interface SettingsTabsProps {
  activeTab: SettingsTab;
  onTabChange: (tab: SettingsTab) => void;
}

const tabs: SettingsTab[] = ["building", "entrances", "flats", "voting"/* , "connections" */];

export default function SettingsTabs({ activeTab, onTabChange }: SettingsTabsProps) {
  const t = useTranslations("Settings");

  const tabLabels: Record<SettingsTab, string> = {
    building: t("tabBuilding"),
    entrances: t("tabEntrances"),
    flats: t("tabFlats"),
    voting: t("tabVoting"),
    connections: t("tabConnections"),
  };

  return (
    <div className="border-b border-gray-200 mb-6">
      <nav className="-mb-px flex space-x-6 overflow-x-auto" aria-label="Tabs">
        {tabs.map((tab) => (
          <button
            key={tab}
            onClick={() => onTabChange(tab)}
            className={`whitespace-nowrap py-3 px-1 border-b-2 text-base font-medium transition-colors ${
              activeTab === tab
                ? "border-blue-600 text-blue-600"
                : "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
            }`}
          >
            {tabLabels[tab]}
          </button>
        ))}
      </nav>
    </div>
  );
}
