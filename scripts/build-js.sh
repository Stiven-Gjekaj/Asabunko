#!/bin/sh
# Bundles the JavaScript libraries of the sources into one file of the core package.
# The output is in the repository, so a build of the app does not need Node.
set -eu

cd "$(dirname "$0")/../js"
npm ci --no-audit --no-fund --silent
npx esbuild libraries.js --bundle --minify --format=iife --target=es2020 --legal-comments=eof \
  --outfile=../AsaCore/Sources/AsaCore/Resources/libraries.js
echo "AsaCore/Sources/AsaCore/Resources/libraries.js"
