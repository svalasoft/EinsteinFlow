#!/usr/bin/env python3
"""Compile and check the actual deterministic Swift laser-tracing scene."""
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '.build/trace-checks'
OUTPUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['xcrun', 'swiftc', '-O', '-target', platform.machine() + '-apple-macosx13.0',
    '-module-cache-path', str(OUTPUT / 'module-cache'), str(ROOT / 'EinsteinFlow/HatTiling.swift'),
    str(ROOT / 'EinsteinFlow/TraceScene.swift'), str(Path(__file__).with_name('TraceSceneChecks.swift')),
    '-o', str(OUTPUT / 'checks')], check=True)
subprocess.run([str(OUTPUT / 'checks')], check=True)
