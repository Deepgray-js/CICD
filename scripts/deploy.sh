#!/usr/bin/env bash

set -euo pipefail

APP_DIR="${APP_DIR:-/opt/cicd-app}"
APP_BRANCH="${APP_BRANCH:-main}"
PM2_APP_NAME="${PM2_APP_NAME:-cicd-app}"

echo "[deploy] app dir: ${APP_DIR}"
echo "[deploy] branch: ${APP_BRANCH}"

cd "${APP_DIR}"

git checkout "${APP_BRANCH}"
git pull origin "${APP_BRANCH}"

if [ -f package-lock.json ]; then
  npm ci
else
  npm install
fi

npm run build --if-present

if [ -f ecosystem.config.js ]; then
  pm2 startOrReload ecosystem.config.js --env production
elif pm2 describe "${PM2_APP_NAME}" >/dev/null 2>&1; then
  pm2 reload "${PM2_APP_NAME}" --update-env
else
  pm2 start npm --name "${PM2_APP_NAME}" -- start
fi

pm2 save

echo "[deploy] done"
