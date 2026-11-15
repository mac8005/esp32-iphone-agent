#!/usr/bin/env python3
"""Select the newest published Xcode and reject stale release artifacts."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import urllib.request
import zipfile

CATALOG = 'https://xcodereleases.com/data.json'


def latest_release(rows):
    releases = [r for r in rows if r.get('name') == 'Xcode' and r.get('sdks', {}).get('iOS')]
    latest = max(releases, key=lambda r: r['_versionOrder'])
    if tuple(map(int, latest['sdks']['iOS'][0]['number'].split('.'))) < (27, 3):
        raise RuntimeError('Release catalog predates the verified iOS 27.3 baseline.')
    return latest


def select_xcode(release):
    requested = os.environ.get('REQUESTED_XCODE')
    candidates = [Path(requested)] if requested else []
    if not requested:
        for root in (Path('/Applications'), Path.home() / 'Developer'):
            for pattern in ('Xcode*.app/Contents/Developer', 'Xcode*/Xcode*.app/Contents/Developer'):
                candidates.extend(root.glob(pattern))
    expected_build = release['version']['build']
    expected_sdk = release['sdks']['iOS'][0]['number']
    for developer in candidates:
        version_file = developer.parent / 'version.plist'
        if not version_file.exists():
            continue
        version = plistlib.loads(version_file.read_bytes())
        if version.get('ProductBuildVersion') != expected_build:
            continue
        environment = dict(os.environ, DEVELOPER_DIR=str(developer))
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'],
                                      env=environment, text=True).strip()
        if sdk != expected_sdk:
            raise RuntimeError(f'Xcode {expected_build} needs iOS SDK {expected_sdk}; found {sdk}.')
        print(f'Newest Xcode {release["version"]["number"]} ({expected_build}), iOS SDK {sdk}',
              file=sys.stderr)
        return str(developer)
    raise RuntimeError(f'Install newest Xcode {release["version"]["number"]} ({expected_build}), '
                       f'iOS SDK {expected_sdk}: {release["links"]["download"]["url"]}. '
                       'Refusing to fall back to an older SDK.')


def verify_metadata(name, info, release):
    platform = info.get('DTPlatformName')
    sdk_key = {'iphoneos': 'iOS', 'watchos': 'watchOS'}.get(platform)
    if sdk_key is None:
        raise RuntimeError(f'{name}: unexpected release platform {platform!r}')
    expected_sdk = platform + release['sdks'][sdk_key][0]['number']
    if info.get('DTSDKName') != expected_sdk or info.get('DTXcodeBuild') != release['version']['build']:
        raise RuntimeError(f'{name}: stale SDK/toolchain: {info.get("DTSDKName")}, '
                           f'{info.get("DTXcodeBuild")}; expected {expected_sdk}, '
                           f'{release["version"]["build"]}')
    print(f'Verified {name}: {expected_sdk}, Xcode {info["DTXcodeBuild"]}', file=sys.stderr)


def verify_artifact(path, release):
    if path.is_dir():
        entries = [(str(p), p.read_bytes()) for p in path.rglob('Info.plist')
                   if p.parent.suffix in ('.app', '.appex')]
    else:
        with zipfile.ZipFile(path) as package:
            entries = [(n, package.read(n)) for n in package.namelist()
                       if n.startswith('Payload/') and n.endswith(('.app/Info.plist', '.appex/Info.plist'))]
    if not entries:
        raise RuntimeError(f'No app or extension metadata found in {path}')
    for name, data in entries:
        verify_metadata(name, plistlib.loads(data), release)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', type=Path, help='Archive/app directory or IPA to check before upload')
    args = parser.parse_args()
    # No cached fallback: network/catalog failures must not silently ship an old SDK.
    with urllib.request.urlopen(CATALOG, timeout=30) as response:
        release = latest_release(json.load(response))
    if args.verify:
        verify_artifact(args.verify, release)
    else:
        print(select_xcode(release))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        sys.exit(str(error))
