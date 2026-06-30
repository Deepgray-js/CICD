#!/usr/bin/env bash

set -euo pipefail

APP_DIR="${APP_DIR:-/opt/cicd-app}"
APP_BRANCH="${APP_BRANCH:-main}"
REPO_URL="${REPO_URL:-https://github.com/Deepgray-js/CICD.git}"

echo "[deploy] app dir: ${APP_DIR}"
echo "[deploy] branch: ${APP_BRANCH}"
echo "[deploy] repo url: ${REPO_URL}"

cd "${APP_DIR}"

git config core.filemode false
git remote set-url origin "${REPO_URL}"
git checkout "${APP_BRANCH}"
git pull origin "${APP_BRANCH}"

if [ -f package.json ]; then
  if [ -f package-lock.json ]; then
    npm ci
  else
    npm install
  fi

  npm run build --if-present
else
  echo "[deploy] no package.json, skip npm install/build"
fi

git rev-parse HEAD

echo "[deploy] done"
