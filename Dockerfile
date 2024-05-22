# Gems with native extensions (puma) compile in the full image; the runtime image stays slim.
FROM ruby:3.4.12 AS build
WORKDIR /app
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=test BUNDLE_PATH=/usr/local/bundle
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install --jobs 4 && rm -rf /usr/local/bundle/cache

FROM ruby:3.4.12-slim
WORKDIR /app
ENV RACK_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=test BUNDLE_PATH=/usr/local/bundle
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY . .
RUN useradd --system --create-home --uid 1001 relay && chown -R relay /app/db
USER relay
EXPOSE 4567
CMD ["sh", "-c", "bundle exec rake db:create db:migrate && exec bundle exec puma --bind tcp://0.0.0.0:4567 config.ru"]
