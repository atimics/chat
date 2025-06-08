# Use Node.js 18 LTS as base image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Install system dependencies for native modules
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    sqlite \
    sqlite-dev

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy only the application code (not node_modules)
COPY auth-service.js ./

# Create data directory
RUN mkdir -p /app/data

# Set proper permissions
RUN chown -R node:node /app
USER node

# Expose port
EXPOSE 3002

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3002/health || exit 1

# Start the application
CMD ["npm", "start"]
