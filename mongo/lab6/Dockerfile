FROM node:22-bookworm-slim
WORKDIR /opt/lab6/mongo/lab6
COPY mongo/lab6/package*.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY mongo/lab6/ ./
COPY tests/lab6/ /opt/lab6/tests/lab6/
ENTRYPOINT ["node", "cli.mjs"]
