#!/usr/bin/env bash
# Compile shared SwiftUI source with the paired SkSL resource in place of Metal.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/.." && pwd)"
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    printf 'Usage: %s [xcbuild arguments]\nDefault: local Svala SDK, Swift 6.2.3, native macOS architecture, Release.\nSet SVALA_SDK_PATH to a root or Developer directory for another SDK, including Wasm.\n' "$0"
    exit 0
fi
sdk_path="${SVALA_SDK_PATH:-${SVALA_DEVELOPER_DIR:-${HOME}/BriskUX/.build/nativeHost/release/Developer}}"
sdk_path="${sdk_path%/}"
if [[ "${sdk_path##*/}" == Developer ]]; then
    developer_dir="${sdk_path}"
else
    developer_dir="${sdk_path}/Developer"
fi
xcbuild="${developer_dir}/usr/bin/xcbuild"
if [[ ! -x "${xcbuild}" ]]; then
    printf 'Svala xcbuild was not found at %s. Set SVALA_SDK_PATH to an SDK root or Developer directory.\n' "${xcbuild}" >&2
    exit 1
fi
export SVALA_SDK_PATH="${developer_dir%/Developer}"
export SVALA_DEVELOPER_DIR="${developer_dir}"

sdk_name=macosx
configuration="${SVALA_CONFIGURATION:-Release}"
target_arch="$(uname -m)"
has_configuration=false
has_sdk=false
has_arch=false
previous_argument=''
for argument in "$@"; do
    case "${previous_argument}" in
        -sdk) sdk_name="${argument}" ;;
        -configuration) configuration="${argument}" ;;
        -arch) target_arch="${argument}" ;;
    esac
    case "${argument}" in
        -configuration) has_configuration=true ;;
        -sdk) has_sdk=true ;;
        -arch) has_arch=true ;;
    esac
    previous_argument="${argument}"
done
build_arguments=(
    -prefer xcode
    -project EinsteinFlow.xcodeproj
    -target EinsteinFlow
    -swift "${SVALA_SWIFT_VERSION:-6.2.3}"
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    EXCLUDED_SOURCE_FILE_NAMES=Einstein.metal
    "OTHER_SWIFT_FLAGS=\$(inherited) -module-cache-path \"${project_dir}/.build/svala-module-cache/${sdk_name}/${target_arch}\""
)
if [[ "${has_configuration}" == false ]]; then build_arguments+=(-configuration "${configuration}"); fi
if [[ "${has_sdk}" == false ]]; then build_arguments+=(-sdk macosx); fi
if [[ "${sdk_name}" == macosx ]]; then
    if [[ "${has_arch}" == false ]]; then build_arguments+=(-arch "${target_arch}"); fi
    host_temp_dir="${project_dir}/.build/svala-macosx-intermediates/${configuration}/${target_arch}"
    "${script_dir}/prepare-svala-icon.sh" "${developer_dir}/Assets/AppIcon1024.png" "${host_temp_dir}"
    build_arguments+=(ASSETCATALOG_COMPILER_APPICON_NAME= SVALA_EMBED_CEF=NO "TARGET_TEMP_DIR=${host_temp_dir}")
fi

cd -- "${project_dir}"
exec "${xcbuild}" "${build_arguments[@]}" "$@"
