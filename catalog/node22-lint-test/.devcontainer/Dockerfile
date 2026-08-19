FROM node:22@sha256:0557ac14e0d45d02ed563067b82856ca5e7aa3437fa28d98d4350ea9c3d9494a

# Pinned lint toolchain, baked into the image itself so it does NOT depend on
# what's in the mounted target repo — only the target repo's own app deps (its
# own `npm ci`) stay with the target repo. These are the exact versions verified
# against mcp-dockhand#221 (the fix that closed mcp-dockhand#213):
# scripts/lint-in-container.sh there pins eslint@10.8.1 + the UNIFIED
# typescript-eslint@8.67.0 meta-package (not the older split
# @typescript-eslint/parser + @typescript-eslint/eslint-plugin) + typescript@5.9.3
# — a disposable TypeScript-5 toolchain that sidesteps a target repo's own
# TypeScript-7-preview compiler breaking typescript-eslint@8.
RUN npm install -g typescript@5.9.3 eslint@10.8.1 typescript-eslint@8.67.0
