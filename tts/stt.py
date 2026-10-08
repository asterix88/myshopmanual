import glob, subprocess, traceback
import numpy as np
try:
    from faster_whisper import WhisperModel
    m = WhisperModel('small', device='cpu', compute_type='int8')
    with open('tts/maha/stt.txt', 'w') as out:
        for f in sorted(glob.glob('tts/maha/m-*.mp3')):
            raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', f, '-f', 'f32le', '-ac', '1', '-ar', '16000', '-'], capture_output=True).stdout
            segs, _ = m.transcribe(np.frombuffer(raw, np.float32), language='id')
            out.write(f + ' ' + ' '.join(s.text.strip() for s in segs) + '\n')
except Exception:
    open('tts/maha/stt.txt', 'a').write(traceback.format_exc())
