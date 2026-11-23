#!/usr/bin/env bash
# The SDK linker accepts TARGET_TEMP_DIR/AppIcon.icns. Supply a generated
# standard icon to avoid its invalid @2.png retina iconset filenames.
set -euo pipefail
source_icon="${1:?Pass a 1024px PNG icon}"
output_dir="${2:?Pass the Svala TARGET_TEMP_DIR}"
output_icon="${output_dir}/AppIcon.icns"
if [[ ! -f "${source_icon}" ]]; then
    printf 'Svala SDK icon is missing: %s\n' "${source_icon}" >&2
    exit 1
fi
if [[ -f "${output_icon}" && "${output_icon}" -nt "${source_icon}" ]]; then exit 0; fi
iconset="${output_dir}/AppIcon.iconset"
mkdir -p "${iconset}"
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((points * scale))
        suffix=''
        if [[ "${scale}" == 2 ]]; then suffix='@2x'; fi
        /usr/bin/sips -z "${pixels}" "${pixels}" "${source_icon}" \
            --out "${iconset}/icon_${points}x${points}${suffix}.png" >/dev/null
    done
done
python3 - "${iconset}" "${output_icon}" <<'PY'
from pathlib import Path
import struct
import sys
iconset, output = map(Path, sys.argv[1:])
representations = [(b'icp4', 'icon_16x16.png'), (b'icp5', 'icon_32x32.png'),
                   (b'icp6', 'icon_32x32@2x.png'), (b'ic07', 'icon_128x128.png'),
                   (b'ic08', 'icon_256x256.png'), (b'ic09', 'icon_512x512.png'),
                   (b'ic10', 'icon_512x512@2x.png')]
chunks = []
for tag, filename in representations:
    payload = (iconset / filename).read_bytes()
    if not payload.startswith(b'\x89PNG\r\n\x1a\n'):
        raise SystemExit('Expected PNG icon representation: ' + filename)
    chunks.append(tag + struct.pack('>I', len(payload) + 8) + payload)
body = b''.join(chunks)
output.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
PY
