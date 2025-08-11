# Use Node.js 20 LTS as base image
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Install system dependencies needed for native modules
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    openssh-client

# Ensure we have the correct yarn version (1.x, not 2.x)
# Node alpine images come with yarn pre-installed, but we need to ensure it's 1.x
RUN yarn --version && \
    if [ "$(yarn --version | cut -d. -f1)" -ge "2" ]; then \
        npm uninstall -g yarn && npm install -g yarn@1.22.19; \
    fi

# Copy package files first for better Docker layer caching
COPY package*.json ./
COPY yarn.lock* ./

# Install dependencies
RUN yarn install --frozen-lockfile --network-timeout 100000

# Copy the rest of the application code
COPY . .

# Build the application
RUN yarn rebuild && yarn run bundle

# Create a non-root user for security
RUN addgroup -g 1001 -S codeeditor && \
    adduser -S codeeditor -u 1001

# Change ownership of the app directory to codeeditor user
RUN chown -R codeeditor:codeeditor /app

# Switch to non-root user
USER codeeditor

# Expose the default CodeEditor port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000 || exit 1

# Start the application
CMD ["yarn", "start", "--hostname=0.0.0.0", "--port=3000"]