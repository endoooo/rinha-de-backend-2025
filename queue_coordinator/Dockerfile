# Multi-stage build for production
FROM elixir:1.15-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y build-essential git && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Set production environment
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy source code
COPY lib ./lib

# Compile and create release
RUN mix compile
RUN mix release

# Production stage
FROM elixir:1.15-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y openssl curl && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy release from builder stage
COPY --from=builder /app/_build/prod/rel/queue_coordinator ./queue_coordinator

# Expose port
EXPOSE 8080

# Start the release
CMD ["./queue_coordinator/bin/queue_coordinator", "start"]