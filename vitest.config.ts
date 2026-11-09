import { defineConfig } from 'vitest/config'

// Separate from vite.config.ts so the Figma Make build is untouched.
export default defineConfig({ test: { include: ['src/**/*.test.ts'] } })
