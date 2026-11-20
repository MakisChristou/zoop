import type { SidebarsConfig } from "@docusaurus/plugin-content-docs";

const sidebars: SidebarsConfig = {
  guide: [
    {
      type: "category",
      label: "Start here",
      collapsed: false,
      items: ["get-started", "iphone"],
    },
    {
      type: "category",
      label: "Your server",
      collapsed: false,
      items: ["self-hosting", "help"],
    },
    {
      type: "category",
      label: "Your data",
      collapsed: false,
      items: ["measurements", "data-privacy"],
    },
  ],
};
export default sidebars;
