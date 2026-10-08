"""Voice-over lines through ElevenLabs. Needs ELEVENLABS_API_KEY; the voice
is ELEVEN_VOICE (a voice id or a name from the account's voice list)."""
import json, os, sys, urllib.request

KEY = os.environ.get('ELEVENLABS_API_KEY', '')
if not KEY:
    print('ELEVENLABS_API_KEY secret is not set'); sys.exit(0)
os.makedirs('tts/eleven', exist_ok=True)

def call(url, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 headers={'xi-api-key': KEY, 'content-type': 'application/json'})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()

voices = json.loads(call('https://api.elevenlabs.io/v1/voices'))['voices']
with open('tts/eleven/voices.txt', 'w') as f:
    for v in voices:
        labels = v.get('labels') or {}
        f.write(f"{v['voice_id']}\t{v['name']}\t{labels.get('gender','')}\t{labels.get('accent','')}\t{v.get('category','')}\n")

want = os.environ.get('ELEVEN_VOICE', '').strip()
picked = [v for v in voices if want and (v['voice_id'] == want or v['name'].lower().startswith(want.lower()))]
if want and not picked:
    print(f'voice {want!r} not found'); sys.exit(1)
targets = picked or [v for v in voices if (v.get('labels') or {}).get('gender') == 'male'][:2] + \
          [v for v in voices if (v.get('labels') or {}).get('gender') == 'female'][:1]
lines = [l.strip() for l in open('tts/lines.txt') if l.strip()]
for v in targets:
    slug = v['name'].split()[0].lower()
    for i, line in enumerate(lines, 1):
        audio = call(f"https://api.elevenlabs.io/v1/text-to-speech/{v['voice_id']}?output_format=mp3_44100_128", {
            'text': line,
            'model_id': 'eleven_multilingual_v2',
            'language_code': 'id',
            'voice_settings': {'stability': 0.45, 'similarity_boost': 0.8, 'style': 0.3, 'speed': 1.08},
        })
        open(f'tts/eleven/{slug}-{i}.mp3', 'wb').write(audio)
    print('done', v['name'])
