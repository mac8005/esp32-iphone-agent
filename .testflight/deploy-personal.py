#!/usr/bin/env python3
"""Release this personal app with retained signing and verified TestFlight notes."""
import argparse
import base64
import json
import http.client
import urllib.error
import os
from pathlib import Path
import plistlib
import runpy
import shlex
import subprocess
import time
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('version')
parser.add_argument('build')
parser.add_argument('--finalize-only', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
notes = json.loads((repo / '.testflight' / f'notes-{args.version}.json').read_text())
assert {'en-US', 'zh-Hans'} <= notes.keys()
assert all(0 < len(value) <= 4000 for value in notes.values())
sidepulse = Path('/Users/massimo/Git/sidepulse/.testflight')
for line in (sidepulse / 'config.env').read_text().splitlines():
    if '=' in line and not line.startswith('#'):
        name, value = line.split('=', 1)
        os.environ[name] = os.path.expandvars(os.path.expanduser(shlex.split(value)[0]))
os.environ['DEVELOPER_DIR'] = '/Volumes/MacMiniData/Developer/Xcode-27.1-rc/Xcode-27.1.0-release.candidate.app/Contents/Developer'
root = Path('/Volumes/MacMiniData/Developer/esp32-iphone-agent')
subprocess.run(['/Users/massimo/Git/mac-maintenance/libexec/macmini-data-ready'], check=True)
work = root / 'releases' / f'{args.version}-{args.build}'
if args.finalize_only:
    assert 'UPLOAD SUCCEEDED with no errors' in (work/'upload.log').read_text()
else:
    work.mkdir(parents=True, exist_ok=False)
profiles = json.loads((root / 'signing/profiles.json').read_text())
signing = json.loads(Path('/Users/massimo/.local/share/sidepulse/signing/signing.json').read_text())
lock = '/Users/massimo/Git/mac-maintenance/libexec/ios-release-lock.py'
receipt = work / 'signing-lock.json'
py = str(sidepulse / '.venv/bin/python')
keychain = signing['keychainPath']
original = shlex.split(subprocess.check_output(['security','list-keychains','-d','user'], text=True))
archive = work / 'ESP32Agent.xcarchive'
export = work / 'export'

def run(command, log):
    print(log, flush=True)
    with (work / log).open('w') as output:
        subprocess.run(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT, check=True)

if not args.finalize_only:
    subprocess.run([py, lock, 'acquire', '--receipt', str(receipt), '--label', f'ESP32 Agent {args.build}'], check=True)
    try:
        password = subprocess.check_output(['security','find-generic-password','-s','io.sidepulse.distribution-signing-20260911','-a','release','-w','/Users/massimo/Library/Keychains/login.keychain-db'], text=True).strip()
        subprocess.run(['security','unlock-keychain','-p',password,keychain], check=True)
        del password
        subprocess.run(['security','list-keychains','-d','user','-s',keychain,*original], check=True)
        identity = subprocess.check_output(['security','find-identity','-v','-p','codesigning',keychain], text=True)
        assert signing['sha1'] in identity
        profile_settings = ['IA_APP_PROFILE='+profiles[0]['uuid'], 'IA_ACTIVITY_PROFILE='+profiles[1]['uuid']]
        run(['xcodebuild','archive','-jobs','1','-project','ios/IPhoneAgent.xcodeproj','-scheme','IPhoneAgent','-configuration','Release','-destination','generic/platform=iOS','-archivePath',str(archive),'-derivedDataPath',str(root/'ReleaseDerivedData'),'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD=NO','DEVELOPMENT_TEAM='+os.environ['APPLE_TEAM_ID'],'MARKETING_VERSION='+args.version,'CURRENT_PROJECT_VERSION='+args.build,'CODE_SIGN_STYLE=Manual','CODE_SIGN_IDENTITY='+signing['sha1'],'OTHER_CODE_SIGN_FLAGS=--keychain '+keychain,*profile_settings], 'archive.log')
        app = archive / 'Products/Applications/IPhoneAgent.app'
        info = plistlib.loads((app/'Info.plist').read_bytes())
        assert info['CFBundleVersion'] == args.build and info['CFBundleShortVersionString'] == args.version
        assert info.get('IAPresetKey','') == ''
        assert info['IAPresetBaseURL'] == 'https://api.openai.com/v1'
        assert info['IAPresetModel'] == 'gpt-6.1-sol'
        assert len(base64.b64decode(info['IAPresetWrappingKey'])) == 32
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
        options = {'method':'app-store-connect','destination':'export','signingStyle':'manual','teamID':os.environ['APPLE_TEAM_ID'],'signingCertificate':signing['sha1'],'provisioningProfiles':{p['bundle']:p['uuid'] for p in profiles},'testFlightInternalTestingOnly':True,'manageAppVersionAndBuildNumber':False,'uploadSymbols':True}
        export_options = work/'ExportOptions.plist'
        export_options.write_bytes(plistlib.dumps(options))
        run(['xcodebuild','-exportArchive','-archivePath',str(archive),'-exportPath',str(export),'-exportOptionsPlist',str(export_options),'OTHER_CODE_SIGN_FLAGS=--keychain '+keychain], 'export.log')
    finally:
        subprocess.run(['security','list-keychains','-d','user','-s',*original],check=True)
        subprocess.run([py,lock,'release','--receipt',str(receipt)],check=True)

    ipa = next(export.glob('*.ipa'))
    provider_key = next(line.split('=',1)[1].strip().strip('\"\'') for line in Path('/Users/massimo/Git/aura/.env').read_text().splitlines() if line.startswith('OPENAI_API_KEY='))
    with zipfile.ZipFile(ipa) as package:
        assert all(provider_key.encode() not in package.read(name) for name in package.namelist())
    del provider_key
    run(['xcrun','altool','--upload-app','--type','ios','--file',str(ipa),'--apiKey',os.environ['ASC_KEY_ID'],'--apiIssuer',os.environ['ASC_ISSUER_ID']], 'upload.log')
api = runpy.run_path(str(sidepulse/'lib/finalize-testflight.py'))
def request(method,path,body=None):
    for attempt in range(3):
        try:
            status,result = api['request'](method,path,api['make_token'](),body)
            return api['expect'](status,result,(200,201,204),'ESP32 TestFlight')
        except (http.client.RemoteDisconnected, urllib.error.URLError, TimeoutError):
            if method != 'GET' or attempt == 2: raise
            time.sleep(5)
app_id = '6823679885'
for attempt in range(60):
    builds = request('GET',f'/v1/builds?filter[app]={app_id}&filter[version]={args.build}&include=preReleaseVersion')['data']
    if builds:
        build = builds[0]
        state = build['attributes']['processingState']
        print('Processing:',state,flush=True)
        if state == 'VALID': break
        if state in ('FAILED','INVALID'): raise RuntimeError('Apple rejected build: '+state)
    time.sleep(30)
else: raise RuntimeError('Apple processing timeout')
build_id = build['id']
version = request('GET',f'/v1/builds/{build_id}/preReleaseVersion')['data']['attributes']['version']
assert version == args.version
existing = request('GET',f'/v1/builds/{build_id}/betaBuildLocalizations')['data']
by_locale = {row['attributes']['locale']:row['id'] for row in existing}
assert set(by_locale) <= notes.keys()
for locale, value in notes.items():
    if locale in by_locale:
        identifier = by_locale[locale]
        request('PATCH',f'/v1/betaBuildLocalizations/{identifier}',{'data':{'type':'betaBuildLocalizations','id':identifier,'attributes':{'whatsNew':value}}})
    else:
        request('POST','/v1/betaBuildLocalizations',{'data':{'type':'betaBuildLocalizations','attributes':{'locale':locale,'whatsNew':value},'relationships':{'build':{'data':{'type':'builds','id':build_id}}}}})
verified = {row['attributes']['locale']:row['attributes']['whatsNew'] for row in request('GET',f'/v1/builds/{build_id}/betaBuildLocalizations')['data']}
assert verified == notes
token = api['make_token']()
group = api['find_or_create_group'](token,app_id,'Personal Testing')
holder = api['account_holder'](token)
assert 'ACCOUNT_HOLDER' in holder['attributes']['roles']
tester = api['find_or_create_tester'](token,holder)
api['link'](token,f"/v1/betaGroups/{group['id']}/relationships/betaTesters",'betaTesters',tester['id'],'Add owner')
api['link'](token,f"/v1/betaGroups/{group['id']}/relationships/builds",'builds',build_id,'Add build')
assert build_id in [row['id'] for row in request('GET',f"/v1/betaGroups/{group['id']}/builds")['data']]
assert tester['id'] in [row['id'] for row in request('GET',f"/v1/betaGroups/{group['id']}/betaTesters")['data']]
summary = {'appId':app_id,'version':args.version,'build':args.build,'buildId':build_id,'group':group['attributes']['name'],'notes':verified,'betaState':request('GET',f'/v1/builds/{build_id}/buildBetaDetail')['data']['attributes']}
(work/'release.json').write_text(json.dumps(summary,indent=2))
print('TestFlight group and notes verified:',work/'release.json',flush=True)
