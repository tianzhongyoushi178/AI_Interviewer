FROM ruby:3.1.6-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential libpq-dev libsqlite3-dev nodejs npm git curl ffmpeg && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --without development test

COPY . .

RUN mkdir -p tmp/pids log storage db

# アセットプリコンパイル（本番用）
ENV RAILS_ENV=production
ENV SECRET_KEY_BASE=placeholder_for_precompile
RUN bundle exec rails assets:precompile

EXPOSE 3000

CMD ["bash", "-c", "bundle exec rails db:prepare && bundle exec rails server -b 0.0.0.0 -p 3000"]
