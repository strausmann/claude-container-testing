FROM node:22@sha256:0557ac14e0d45d02ed563067b82856ca5e7aa3437fa28d98d4350ea9c3d9494a

# Pinned TS-5-compatible eslint toolchain, baked into the image itself so it does
# NOT depend on what's in the mounted target repo — only the target repo's own
# app deps (its own `npm ci`) stay with the target repo. This is the fix for
# mcp-dockhand#213: the target repo's local TypeScript-7-preview compiler broke
# typescript-eslint@8; a disposable TypeScript-5 toolchain sidesteps the conflict.
RUN npm install -g typescript@5.6.3 eslint@9.13.0 @typescript-eslint/parser@8.13.0 \
    @typescript-eslint/eslint-plugin@8.13.0
