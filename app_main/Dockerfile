FROM node:20-alpine

WORKDIR /app

# Install build dependencies for native modules
RUN apk add --no-cache python3 make g++ libc6-compat linux-headers eudev-dev

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application files
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S webclient -u 1001

# Change ownership
RUN chown -R webclient:nodejs /app
USER webclient

EXPOSE 3000

CMD ["npm", "start"]
