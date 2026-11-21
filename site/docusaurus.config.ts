import type { Config } from "@docusaurus/types";
import type { Options, ThemeConfig } from "@docusaurus/preset-classic";
import { themes } from "prism-react-renderer";

const config: Config = {
  title: "Zoop",
  tagline: "Your wearable data. Your server.",
  url: "https://zoop.health",
  baseUrl: "/",
  favicon: "img/zoop.svg",
  organizationName: "MakisChristou",
  projectName: "zoop",
  trailingSlash: true,
  onBrokenLinks: "throw",
  markdown: { hooks: { onBrokenMarkdownLinks: "throw" } },
  noIndex: false,
  i18n: { defaultLocale: "en", locales: ["en"] },
  presets: [
    [
      "classic",
      {
        docs: {
          path: "../docs",
          include: [
            "GET_STARTED.md",
            "SELF_HOSTING.md",
            "IPHONE_SETUP.md",
            "METRICS_GUIDE.md",
            "HELP.md",
            "DATA_PRIVACY.md",
          ],
          sidebarPath: "./sidebars.ts",
          editUrl: "https://github.com/MakisChristou/zoop/edit/main/docs/",
        },
        blog: false,
        theme: { customCss: "./src/css/custom.css" },
      } satisfies Options,
    ],
  ],
  themes: [
    [
      "@easyops-cn/docusaurus-search-local",
      {
        hashed: true,
        language: "en",
        indexBlog: false,
        indexPages: false,
        docsDir: "../docs",
        docsRouteBasePath: "/docs",
        highlightSearchTermsOnTargetPage: true,
      },
    ],
  ],
  themeConfig: {
    colorMode: { defaultMode: "dark", respectPrefersColorScheme: false },
    navbar: {
      title: "zoop",
      logo: { alt: "", src: "img/zoop.svg", width: 28, height: 28 },
      items: [
        { to: "/docs/get-started", label: "Docs", position: "left" },
        {
          href: "https://github.com/MakisChristou/zoop",
          label: "GitHub",
          position: "right",
        },
      ],
    },
    footer: {
      links: [
        {
          title: "Get started",
          items: [
            { label: "Install Zoop", to: "/docs/get-started" },
            { label: "Connect your iPhone", to: "/docs/iphone" },
            { label: "Troubleshooting", to: "/docs/help" },
          ],
        },
        {
          title: "Understand your data",
          items: [
            { label: "Measurements", to: "/docs/measurements" },
            { label: "Data & privacy", to: "/docs/data-privacy" },
            {
              label: "Backups & updates",
              to: "/docs/self-hosting#back-up-and-restore",
            },
          ],
        },
        {
          title: "Project",
          items: [
            {
              label: "Source code",
              href: "https://github.com/MakisChristou/zoop",
            },
            {
              label: "Contribute",
              href: "https://github.com/MakisChristou/zoop/blob/main/CONTRIBUTING.md",
            },
            {
              label: "MIT license",
              href: "https://github.com/MakisChristou/zoop/blob/main/LICENSE",
            },
          ],
        },
      ],
      copyright: "Zoop is an independent project. Not affiliated with WHOOP.",
    },
    prism: {
      theme: {
        ...themes.github,
        styles: themes.github.styles.map((rule) => ({
          ...rule,
          style: {
            ...rule.style,
            color:
              (
                {
                  "#999988": "#676758",
                  "#e3116c": "#a80e50",
                  "#36acaa": "#276968",
                  "#00a4db": "#006f96",
                  "#d73a49": "#b22937",
                } as Record<string, string>
              )[rule.style.color ?? ""] ?? rule.style.color,
          },
        })),
      },
      darkTheme: themes.vsDark,
      additionalLanguages: ["bash", "toml", "yaml"],
    },
    tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 3 },
  } satisfies ThemeConfig,
};
export default config;
