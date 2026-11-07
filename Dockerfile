# syntax=docker/dockerfile:1.7

# Build the browser application. Vite embeds VITE_* values at build time.
FROM node:22-alpine AS frontend-build
WORKDIR /app
COPY package.json ./
RUN npm install --no-audit --no-fund
COPY index.html ./
COPY vite.config.ts tsconfig.json tsconfig.app.json tsconfig.node.json ./
COPY src ./src
ARG VITE_GOOGLE_CLIENT_ID=
ENV VITE_GOOGLE_CLIENT_ID=${VITE_GOOGLE_CLIENT_ID}
RUN npm run build

# The API image contains only production dependencies and server code.
FROM node:22-alpine AS api
ENV NODE_ENV=production PORT=4000
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund \
    && npm cache clean --force
COPY --chown=node:node server ./server
USER node
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:4000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server/index.js"]

# Static SPA container. The edge gateway routes /api to the API container.
FROM nginx:stable-alpine AS frontend
COPY deploy/frontend.nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=frontend-build /app/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=5 \
  CMD wget -q --spider http://127.0.0.1:8080/health || exit 1
