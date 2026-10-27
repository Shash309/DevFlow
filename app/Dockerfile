FROM node:20-alpine

WORKDIR /usr/src/app
ENV NODE_ENV=production

COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src

ARG BUILD_NUMBER=dev
ENV BUILD_NUMBER=${BUILD_NUMBER} \
    PORT=3000

EXPOSE 3000
USER node

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "src/server.js"]
