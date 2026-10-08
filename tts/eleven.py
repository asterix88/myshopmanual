"""Voice-over lines and background music through ElevenLabs. Needs
ELEVENLABS_API_KEY. tts/voice.txt holds a voice id (or a name from the
account's list); tts/music.txt holds the music prompt."""
import json, os, sys, urllib.request, urllib.error

KEY = os.environ.get('ELEVENLABS_API_KEY', '')
if not KEY:
    print('ELEVENLABS_API_KEY secret is not set'); sys.exit(0)
os.makedirs('tts/eleven', exist_ok=True)

def call(url, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 headers={'xi-api-key': KEY, 'content-type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        print('HTTP', e.code, url.split('?')[0], e.read()[:400])
        return None

want = open('tts/voice.txt').read().strip() if os.path.exists('tts/voice.txt') else ''
voices = json.loads(call('https://api.elevenlabs.io/v1/voices') or b'{"voices":[]}')['voices']
named = [v for v in voices if want and v['name'].lower().startswith(want.lower())]
voice_id = named[0]['voice_id'] if named else want
lines = [l.strip() for l in open('tts/lines.txt') if l.strip()]
# tts/takes.txt: "line|name|stability|style|speed" per row -> extra takes v-<line><name>.mp3 only.
if os.path.exists('tts/takes.txt'):
    for row in open('tts/takes.txt'):
        if not row.strip(): continue
        n, name, stab, style, speed = row.strip().split('|')
        audio = call(f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=mp3_44100_128", {
            'text': lines[int(n) - 1], 'model_id': 'eleven_multilingual_v2', 'language_code': 'id',
            'voice_settings': {'stability': float(stab), 'similarity_boost': 0.85, 'style': float(style),
                               'use_speaker_boost': True, 'speed': float(speed)}})
        if audio:
            open(f'tts/eleven/v-{n}{name}.mp3', 'wb').write(audio)
    print('takes done', voice_id); sys.exit(0)
for i, line in enumerate(lines, 1):
    audio = call(f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=mp3_44100_128", {
        'text': line,
        'model_id': 'eleven_multilingual_v2',
        'language_code': 'id',
        'voice_settings': {'stability': 0.2 if i == len(lines) else 0.3, 'similarity_boost': 0.85, 'style': 0.9 if i == len(lines) else 0.65, 'use_speaker_boost': True, 'speed': 1.12},
    })
    if audio:
        open(f'tts/eleven/v-{i}.mp3', 'wb').write(audio)
print('voice lines done', voice_id)

if os.path.exists('tts/music.txt'):
    prompt = open('tts/music.txt').read().strip()
    music = call('https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128',
                 {'prompt': prompt, 'music_length_ms': 33000, 'force_instrumental': True})
    if music:
        open('tts/eleven/music.mp3', 'wb').write(music); print('music done')
    else:
        for n in (1, 2):
            fx = call('https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128',
                      {'text': prompt, 'duration_seconds': 22, 'prompt_influence': 0.5})
            if fx:
                open(f'tts/eleven/music-fx{n}.mp3', 'wb').write(fx); print('sound-generation music done', n)
