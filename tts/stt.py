from faster_whisper import WhisperModel
import glob
m = WhisperModel('small', device='cpu', compute_type='int8')
with open('tts/maha/stt.txt', 'w') as out:
    for f in sorted(glob.glob('tts/maha/m-*.mp3')):
        segs, _ = m.transcribe(f, language='id')
        out.write(f + ' ' + ' '.join(s.text.strip() for s in segs) + '\n')
