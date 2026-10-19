#!/usr/bin/env bash
# Render build step: install gems, migrate, and (optionally) load demo data.
# Render's free tier has no separate pre-deploy hook, so migrations run here.
set -o errexit

bundle install
bin/rails db:migrate

if [ "${SEED_DEMO_DATA:-false}" = "true" ]; then
  bin/rails db:seed
fi
