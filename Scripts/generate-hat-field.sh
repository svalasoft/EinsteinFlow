#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/.." && pwd)"
build_dir="${project_dir}/.build/hat-field-generator"
mkdir -p "${build_dir}"
xcrun swiftc -O -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "${build_dir}/module-cache" \
    "${project_dir}/EinsteinFlow/HatTiling.swift" \
    "${script_dir}/HatFieldSupport.swift" \
    "${script_dir}/GenerateHatField.swift" -o "${build_dir}/generate-hat-field"
"${build_dir}/generate-hat-field" "${project_dir}/EinsteinFlow/Assets.xcassets/HatField.imageset"
