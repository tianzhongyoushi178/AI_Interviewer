FROM ruby:3.1.6-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential libsqlite3-dev nodejs npm git curl ffmpeg && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4

COPY . .

RUN mkdir -p tmp/pids log storage db

EXPOSE 3000

CMD ["bash", "-c", "bundle exec rails db:prepare && bundle exec rails server -b 0.0.0.0 -p 3000"]
