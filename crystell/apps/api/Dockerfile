FROM ruby:3.4.5-alpine

RUN apk add --no-cache build-base postgresql-dev tzdata

WORKDIR /app
COPY Gemfile ./
RUN bundle install
COPY . .

ENV RAILS_ENV=development
EXPOSE 3001
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3001"]
