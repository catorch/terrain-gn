# Build from the repo root: docker build -f api/Dockerfile .
FROM node:24-slim
WORKDIR /app/api
RUN corepack enable
COPY api/package.json api/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY api/tsconfig.json ./
COPY api/src ./src
COPY sql /app/sql
RUN pnpm build && pnpm prune --prod
ENV NODE_ENV=production
EXPOSE 4100
CMD ["sh", "-c", "node dist/migrate.js && node dist/main.js"]
