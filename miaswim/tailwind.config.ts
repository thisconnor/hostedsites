import type { Config } from 'tailwindcss';

// Theme tokens per SPEC.md §5.10 — working palette (blue for swimming,
// summery and fun). Values live in globals.css as CSS variables so Mia's
// final hex picks swap in without rework.
const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        pool: 'var(--color-pool)', // deep water blue — headers/CTAs
        aqua: 'var(--color-aqua)', // bright aqua — accents
        coral: 'var(--color-coral)', // warm summer accent
        sand: 'var(--color-sand)', // light, airy neutral
        ink: 'var(--color-ink)',
      },
    },
  },
  plugins: [],
};

export default config;
