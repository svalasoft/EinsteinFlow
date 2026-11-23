#!/usr/bin/env bash
# Build only; pass signing overrides explicitly for unsigned simulator/CI builds.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/.." && pwd)"
if [[ "${1:-}" == build ]]; then shift; fi
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    printf 'Usage: %s [build] [xcodebuild arguments]\nDefault destination: My Mac (Mac Catalyst).\n' "$0"
    exit 0
fi

xcode_args=(-project "${project_dir}/EinsteinFlow.xcodeproj" -scheme EinsteinFlow)
has_destination=false
has_configuration=false
has_derived_data=false
for argument in "$@"; do
    case "${argument}" in
        -destination) has_destination=true ;;
        -configuration) has_configuration=true ;;
        -derivedDataPath) has_derived_data=true ;;
    esac
done
if [[ "${has_destination}" == false ]]; then
    xcode_args+=(-destination "${XCODE_DESTINATION:-platform=macOS,variant=Mac Catalyst}")
fi
if [[ "${has_configuration}" == false ]]; then
    xcode_args+=(-configuration "${XCODE_CONFIGURATION:-Debug}")
fi
if [[ "${has_derived_data}" == false ]]; then
    xcode_args+=(-derivedDataPath "${XCODE_DERIVED_DATA:-${project_dir}/.build/xcode}")
fi

cd -- "${project_dir}"
exec xcodebuild "${xcode_args[@]}" "$@" build
