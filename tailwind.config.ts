import type { Config } from "tailwindcss";
const config: Config = {
  darkMode: "class",
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: { extend: { colors: { brand: { DEFAULT: "#2a78d6", dark: "#3987e5" } } } },
  plugins: [],
};
export default config;
