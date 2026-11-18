FROM node:20-alpine

WORKDIR /usr/src/app
ENV NODE_ENV=production

COPY package*.json ./
# npm is only needed to install dependencies; removing it drops its bundled packages
# (e.g. tar) from the runtime image, so Trivy has fewer vulnerabilities to report
RUN npm ci --omit=dev \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack /opt/yarn* \
           /usr/local/bin/yarn /usr/local/bin/yarnpkg /root/.npm

COPY src ./src

ARG BUILD_NUMBER=dev
ENV BUILD_NUMBER=${BUILD_NUMBER} \
    PORT=3000

EXPOSE 3000
USER node

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "src/server.js"]
