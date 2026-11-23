#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/.." && pwd)"
if ! command -v xcodegen >/dev/null 2>&1; then
    printf 'Install XcodeGen to regenerate EinsteinFlow.xcodeproj from project.yml.\n' >&2
    exit 1
fi
cd -- "${project_dir}"
exec xcodegen generate --spec project.yml
