# Use Node.js 18 LTS as base image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Install system dependencies needed for native modules
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    openssh-client

# Install yarn in the version range specified in package.json (>=1.7.0 <2)
RUN npm install -g yarn@1.22.19

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
RUN addgroup -g 1001 -S theia && \
    adduser -S theia -u 1001

# Change ownership of the app directory to theia user
RUN chown -R theia:theia /app

# Switch to non-root user
USER theia

# Expose the default Theia port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000 || exit 1

# Start the application
CMD ["yarn", "start", "--hostname=0.0.0.0", "--port=3000"]