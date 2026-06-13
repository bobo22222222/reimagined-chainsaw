import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        ink: {
          900: "#0b0d12",
          800: "#121620",
          700: "#1a1f2e",
          600: "#242b3d",
          500: "#323a52",
        },
        brand: {
          400: "#f59e0b",
          500: "#f97316",
          600: "#ea580c",
        },
      },
    },
  },
  plugins: [],
};

export default config;
