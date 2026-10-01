#!/usr/bin/env bash
# Runs the API tests against a throw-away Postgres database. Refuses to touch anything not named *test*.
#   TEST_DATABASE_URL=postgresql://user:pw@localhost:5432/healthdiary_test npm test
set -euo pipefail
: "${TEST_DATABASE_URL:?set TEST_DATABASE_URL to an empty database whose name contains 'test'}"
case "$TEST_DATABASE_URL" in *test*) ;; *) echo "refusing: database name must contain 'test'"; exit 1;; esac
export DATABASE_URL="$TEST_DATABASE_URL"
npx prisma db push --force-reset --skip-generate >/dev/null
npx tsx --test --test-concurrency=1 test/*.test.ts
