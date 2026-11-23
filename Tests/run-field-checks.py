#!/usr/bin/env python3
"""Verify expandable substitution windows without UI, shaders, or huge patches."""
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '.build/field-checks'
OUTPUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['xcrun', 'swiftc', '-O', '-target', platform.machine() + '-apple-macosx13.0',
    '-module-cache-path', str(OUTPUT / 'module-cache'), str(ROOT / 'EinsteinFlow/HatTiling.swift'),
    str(ROOT / 'EinsteinFlow/TraceScene.swift'), str(Path(__file__).with_name('HatFieldChecks.swift')),
    '-o', str(OUTPUT / 'checks')], check=True)
subprocess.run([str(OUTPUT / 'checks')], check=True)
