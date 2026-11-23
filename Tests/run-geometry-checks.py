#!/usr/bin/env python3
"""Validate the real Swift hat substitution and the shipped opaque field asset."""
from pathlib import Path
import json
import os
import platform
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '.build' / 'geometry-checks'
OUTPUT.mkdir(parents=True, exist_ok=True)
command = ['xcrun', 'swiftc', '-O', '-target', platform.machine() + '-apple-macosx13.0',
    '-module-cache-path', str(OUTPUT / 'module-cache'),
    str(ROOT / 'EinsteinFlow/HatTiling.swift'), str(ROOT / 'Scripts/HatFieldSupport.swift'),
    str(Path(__file__).with_name('HatGeometryChecks.swift')), '-o', str(OUTPUT / 'checks')]
subprocess.run(command, check=True)
subprocess.run([str(OUTPUT / 'checks')], check=True)
asset = ROOT / 'EinsteinFlow/Assets.xcassets/HatField.imageset'
data = (asset / 'HatField.png').read_bytes()
assert data[:8] == b'\x89PNG\r\n\x1a\n'
width, height, bits, color = struct.unpack('>IIBB', data[16:26])
assert (width, height, bits, color) == (3072, 3072, 8, 2), (width, height, bits, color)
contents = json.loads((asset / 'Contents.json').read_text())
assert contents['images'] == [{'filename': 'HatField.png', 'idiom': 'universal', 'scale': '1x'}]
print('Asset: 3072×3072, 8-bit RGB, no alpha, universal 1x catalog entry.')
