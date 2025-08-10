FROM elixir:1.15.4-alpine

WORKDIR /app

RUN apk add --no-cache build-base git

COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix deps.compile

COPY . .
RUN mix compile

EXPOSE 9999

CMD ["mix", "phx.server"]