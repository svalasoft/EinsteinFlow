#!/usr/bin/env python3
"""Compile the app's actual SkSL and exercise it on the native Skia GPU backend."""
import argparse
from pathlib import Path
import platform
import re
import subprocess
import tempfile


def check_shared_math(app):
    """Reject a drift between the two API entry points' actual calculations."""
    metal = (app / 'EinsteinFlow/Einstein.metal').read_text()
    sksl = (app / 'EinsteinFlow/einsteinFlow.sksl').read_text()

    def normalize(source):
        source = re.sub(r'//[^\n]*|/\*.*?\*/', '', source, flags=re.S)
        source = re.sub(r'sample\(svala_layer,\s*', 'layer.sample(', source)
        return re.sub(r'\s+', '', source)

    metal_start = metal.index('[[ stitchable ]]')
    metal_body = metal[metal.index('{', metal_start) + 1:metal.rindex('}')]
    sksl_start = sksl.index('half4 main(')
    sksl_body = sksl[sksl.index('{', sksl_start) + 1:sksl.rindex('}')]
    declarations = ['float2 size = svala_arg0;', 'float4 state = svala_arg1;']
    declarations += [f'float4 head{i} = svala_arg{i+2};' for i in range(8)]
    declarations += ['float4 powers0 = svala_arg10;', 'float4 powers1 = svala_arg11;']
    for declaration in declarations:
        sksl_body = sksl_body.replace(declaration, '', 1)
    assert normalize(metal_body) == normalize(sksl_body), 'Metal/SkSL entry-point calculations diverged'
    metal_helpers = metal[metal.index('float einsteinSmooth('):metal_start]
    sksl_helpers = sksl[sksl.index('float einsteinSmooth('):sksl_start]
    assert normalize(metal_helpers) == normalize(sksl_helpers), 'Metal/SkSL helper calculations diverged'
    print('PASS: Metal and SkSL calculations match after API-only substitutions', flush=True)


def main():
    app = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--svala-root', type=Path, default=Path.home() / 'BriskUX')
    parser.add_argument('--build-dir', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--image', type=Path, help='Actual HatField asset; omitted runs a synthetic shader-only fixture')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('This offscreen GPU fixture currently requires macOS; it does not imply other runtime results.')
    root = args.svala_root.resolve()
    check_shared_math(app)
    build = (args.build_dir or root / '.build/nativeHost/releaseShared').resolve()
    output = args.output or Path(tempfile.mkdtemp(prefix='einstein-shader-checks-', dir='/tmp'))
    output.mkdir(parents=True, exist_ok=True)
    binary = output / 'shader-gpu-checks'
    command = ['xcrun', 'clang++', '-std=c++17', '-Wno-deprecated-declarations',
               str(Path(__file__).with_name('ShaderGPUChecks.cpp')), '-I', str(root / 'External/skia'),
               str(build / 'lib/libskia.a')]
    for framework in ['OpenGL', 'Foundation', 'Metal', 'CoreGraphics', 'CoreText', 'ImageIO', 'QuartzCore']:
        command += ['-framework', framework]
    subprocess.run(command + ['-lz', '-o', str(binary)], check=True)
    shader = app / 'EinsteinFlow/einsteinFlow.sksl'
    image = str(args.image.resolve()) if args.image else '-'
    print('Actual shader:', shader, flush=True)
    print('Source image:', image, flush=True)
    print('Artifacts:', output, flush=True)
    subprocess.run([str(binary), str(shader), image, str(output)], check=True, timeout=90)


if __name__ == '__main__':
    main()
