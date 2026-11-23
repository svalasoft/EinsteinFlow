#!/usr/bin/env python3
"""Verify persistent world-space navigation without a UI runtime."""
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '.build/camera-checks'
OUTPUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['xcrun', 'swiftc', '-O', '-target', platform.machine() + '-apple-macosx13.0',
    '-module-cache-path', str(OUTPUT / 'module-cache'), str(ROOT / 'EinsteinFlow/HatTiling.swift'),
    str(ROOT / 'EinsteinFlow/CameraNavigation.swift'), str(Path(__file__).with_name('CameraNavigationChecks.swift')),
    '-o', str(OUTPUT / 'checks')], check=True)
subprocess.run([str(OUTPUT / 'checks')], check=True)
