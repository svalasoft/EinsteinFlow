#!/usr/bin/env python3
"""Exercise distributed laser scheduling and finite fill preservation without UI."""
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '.build/construction-checks'
OUTPUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['xcrun', 'swiftc', '-O', '-target', platform.machine() + '-apple-macosx13.0',
    '-module-cache-path', str(OUTPUT / 'module-cache'), str(ROOT / 'EinsteinFlow/HatTiling.swift'),
    str(ROOT / 'EinsteinFlow/TraceScene.swift'), str(ROOT / 'EinsteinFlow/LaserConstruction.swift'),
    str(Path(__file__).with_name('ConstructionChecks.swift')),
    '-o', str(OUTPUT / 'checks')], check=True)
subprocess.run([str(OUTPUT / 'checks')], check=True, timeout=120)
