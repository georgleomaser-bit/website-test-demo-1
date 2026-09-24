# AKYTEX-Server als Container (z. B. auf einem VPS): docker build -t akytex . && docker run -d -p 8080:8080 -v akytex-data:/data -e ADMIN_TOKEN=... akytex
FROM node:22-alpine
WORKDIR /app
COPY . .
ENV PORT=8080 DATA_DIR=/data NODE_ENV=production
RUN mkdir -p /data && chown node:node /data
USER node
EXPOSE 8080
CMD ["node", "server/akytex-server.mjs"]
