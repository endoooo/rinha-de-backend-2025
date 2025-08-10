# Build stage - unlimited resources for compilation
FROM elixir:1.15.4-alpine AS builder

WORKDIR /app

RUN apk add --no-cache build-base git

COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod
RUN mix deps.get --only=prod && \
    mix deps.compile

COPY . .
RUN mix compile && \
    mix release

# Runtime stage - subject to resource constraints
FROM alpine:3.18 AS runtime

RUN apk add --no-cache libgcc libstdc++ ncurses-libs

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/payment_processor ./

ENV PHX_SERVER=true
ENV MIX_ENV=prod

EXPOSE 9999

CMD ["sh", "-c", "./bin/payment_processor eval 'PaymentProcessor.Release.migrate()' && ./bin/payment_processor start"]