FROM alpine:latest

# Install required tools: git, curl, jq, bash, coreutils
RUN apk add --no-cache git curl jq bash coreutils

# Create app directory
WORKDIR /app

# Copy script
COPY mirror.sh .

# Make script executable
RUN chmod +x mirror.sh

# Default command
CMD ["./mirror.sh"]
