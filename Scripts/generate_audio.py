import math, random, struct, wave
from pathlib import Path
OUT = Path(__file__).resolve().parents[1] / 'Resources'
SR = 22050
random.seed(7)
def write(name, samples):
    peak = max(1.0, max(abs(v) for v in samples))
    with wave.open(str(OUT / (name + '.wav')), 'w') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes(b''.join(struct.pack('<h', round(max(-1,min(1,x/peak))*28000)) for x in samples))
def effect(name, duration, f0, f1, grit=0):
    data=[]; phase=0
    for i in range(int(SR*duration)):
        t=i/SR; u=t/duration; freq=f0+(f1-f0)*u
        phase+=2*math.pi*freq/SR
        env=min(1,t/0.008)*(1-u)**2
        data.append(env*(math.sin(phase)*0.55 + math.sin(phase*2)*0.15 + random.uniform(-1,1)*grit))
    write(name,data)
effect('coin',.18,1300,1800)
effect('jump',.22,250,800)
effect('slide',.19,450,100,.17)
effect('crash',.5,160,35,.5)
effect('shield',.5,95,480,.17)
for name,notes in [('power',[523,659,784,1046]),('start',[392,523,659,784])]:
    data=[0.0]*int(SR*.8)
    for n,freq in enumerate(notes):
        for i in range(int(SR*.4)):
            p=int(n*.10*SR)+i
            if p<len(data):
                t=i/SR; env=min(1,t/.005)*math.exp(-t*10)
                data[p]+=.32*env*(math.sin(t*freq*2*math.pi)+.3*math.sin(t*freq*4*math.pi))
    write(name,data)
# Original 16-second coastal pluck, bass and brushed beat loop (120 BPM).
duration=16; data=[0.0]*(SR*duration)
def tone(start,freq,dur,amp,kind='pluck'):
    for i in range(int(dur*SR)):
        t=i/SR; p=(int(start*SR)+i)%len(data)
        if kind=='bass': env=min(1,t/.014)*math.exp(-t*6); v=math.sin(2*math.pi*freq*t)
        elif kind=='kick': env=math.exp(-t*21); v=math.sin(2*math.pi*(48*t+4*(1-math.exp(-t*25))))
        elif kind=='hat': env=math.exp(-t*65); v=random.uniform(-1,1)
        else: env=min(1,t/.004)*math.exp(-t*8); v=math.sin(2*math.pi*freq*t)+.35*math.sin(4*math.pi*freq*t)+.12*math.sin(6*math.pi*freq*t)
        data[p]+=amp*env*v
chords=[[261.63,329.63,392,493.88],[220,261.63,329.63,392],[174.61,220,261.63,329.63],[196,246.94,293.66,392]]
for beat in range(32):
    chord=chords[(beat//8)%4]
    tone(beat*.5,60,.3,.25,'kick')
    tone(beat*.5+.25,0,.10,.075,'hat')
    tone(beat*.5,chord[0]/2,.45,.24,'bass')
    if beat%2==1: tone(beat*.5,0,.12,.055,'hat')
    for offset,idx in [(0,0),(.25,2),(.375,1)]: tone(beat*.5+offset,chord[(idx+beat//2)%4]*2,.6,.10)
write('coastline',data)
print('Generated 8 original bundled audio assets')
