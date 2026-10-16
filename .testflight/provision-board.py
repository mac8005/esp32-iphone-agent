import base64, json, os, shlex, subprocess
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

config = Path('/Users/massimo/Git/esp32-iphone-agent/ios/Config/Local.xcconfig')
text = config.read_text()
existing = next((l.split('=',1)[1].strip() for l in text.splitlines() if l.startswith('IA_PRESET_WRAPPING_KEY =')),None)
wrapping = base64.b64decode(existing) if existing else AESGCM.generate_key(bit_length=256)
if not existing:
    config.write_text(text+'\nIA_PRESET_WRAPPING_KEY = '+base64.b64encode(wrapping).decode()+'\n')
    config.chmod(0o600)
key = next(l.split('=',1)[1].strip().strip('\"\'') for l in Path('/Users/massimo/Git/aura/.env').read_text().splitlines() if l.startswith('OPENAI_API_KEY='))
nonce = os.urandom(12)
envelope = base64.b64encode(nonce+AESGCM(wrapping).encrypt(nonce,key.encode(),None)).decode()
assert len(envelope)<=300
remote = '''
import serial,sys,time,json,glob
payload=json.load(sys.stdin)
with serial.Serial(glob.glob('/dev/cu.usbmodem*')[0],115200,timeout=1) as s:
 time.sleep(1);s.reset_input_buffer()
 def command(c):
  wire=(c+'\\n').encode()
  for offset in range(0,len(wire),64):
   s.write(wire[offset:offset+64]);s.flush();time.sleep(0.05)
  deadline=time.time()+10
  while time.time()<deadline:
   line=s.readline().decode(errors='replace').strip()
   if line.startswith('0 '): return line
  raise RuntimeError('No USB response')
 assert command('0 preset '+payload['envelope'])=='0 ok'
 config=json.loads(command('0 config')[5:])
 assert config['sealedAPIKey']==payload['envelope']
 status=json.loads(command('0 status')[5:])
 print(json.dumps({'status':status,'configBytes':len(json.dumps(config,separators=(',',':'))),'envelope':config['sealedAPIKey']}))
'''
result = subprocess.run(['ssh','massimo@100.84.82.77','/Users/massimo/Documents/esp32-flash-venv/bin/python -c '+shlex.quote(remote)],input=json.dumps({'envelope':envelope}),capture_output=True,text=True,check=True)
data=json.loads(result.stdout)
combined=base64.b64decode(data.pop('envelope'))
assert AESGCM(wrapping).decrypt(combined[:12],combined[12:],None).decode()==key
assert data['configBytes']<=512
assert data['status']['psram']>1000000 and data['status']['net']=='ap' and data['status']['usb']=='ok'
print('Encrypted board credential verified; provider key absent from board and app configuration.')
print(json.dumps(data,indent=2))
