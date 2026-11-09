"""Social banners en OG-afbeeldingen voor lrvdlinden.app (NL en EN).
Gebruik: python3 tools/social/gen.py /pad/naar/out && node tools/social/shot.js /pad/naar/out/jobs.json
"""
import json, os, sys
SITE=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'site'))
FONTS=os.path.abspath(os.environ.get('FONTS', 'node_modules/@fontsource'))  # npm i @fontsource/bricolage-grotesque@5 @fontsource/hanken-grotesk@5
OUT=sys.argv[1]
apps=json.load(open(f'{SITE}/apps.json'))['apps']
icons=list(dict.fromkeys([a['icon'] for a in apps if a.get('icon') and a['icon'].endswith(('.webp','.png')) and os.path.isfile(f"{SITE}/{a['icon']}")]))
logo=open(f'{SITE}/logo.svg').read(); logo=logo[logo.index('<svg'):]
T={'nl':dict(h='Apps voor je buurt, je huis en <em>je&nbsp;dag</em>.',sub='Gratis iOS- en Homey-apps van Léon van der Linden',chips=['iPhone','iPad','Mac','Homey'],cta='Ontdek alle apps',free='Gratis · zonder advertenties'),
   'en':dict(h='Apps for your neighbourhood, your home and <em>your&nbsp;day</em>.',sub='Free iOS and Homey apps by Léon van der Linden',chips=['iPhone','iPad','Mac','Homey'],cta='Discover all apps',free='Free · no ads')}
ff=''.join(f'@font-face{{font-family:"{f}";font-weight:{w};src:url(file://{FONTS}/{p})}}' for f,p,w in [
 ("Bricolage Grotesque","bricolage-grotesque/files/bricolage-grotesque-latin-700-normal.woff2",700),("Bricolage Grotesque","bricolage-grotesque/files/bricolage-grotesque-latin-800-normal.woff2",800),
 ("Hanken Grotesk","hanken-grotesk/files/hanken-grotesk-latin-500-normal.woff2",500),("Hanken Grotesk","hanken-grotesk/files/hanken-grotesk-latin-600-normal.woff2",600)])
def page(w,h,lang,kind,s):
    t=T[lang]; u=min(w,h)  # basismaat
    n= 40
    cells=''.join(f'<div class="ic"><img src="file://{SITE}/{icons[i%len(icons)]}"></div>' for i in range(n))
    if kind=='wide':
        ic=s.get('ic',128); cols=s.get('cols',5)
        grid=f'right:{s.get("gr",-70)}px;top:{s.get("gt",-60)}px;grid-template-columns:repeat({cols},{ic}px)'
        fade='linear-gradient(90deg,#0D1018 0%,#0D1018 '+str(s.get('f1',54))+'%,rgba(13,16,24,0) '+str(s.get('f2',72))+'%)'
        left=f'left:{s["pad"]}px;top:{s.get("pt",s["pad"])}px;bottom:{s.get("pb",s["pad"])}px;width:{s["tw"]}px;justify-content:{s.get("jc","space-between")}'
    else:
        ic=s.get('ic',150); cols=s.get('cols',6)
        grid=f'left:-40px;top:{s.get("gt",40)}px;grid-template-columns:repeat({cols},{ic}px)'
        fade='linear-gradient(0deg,#0D1018 0%,#0D1018 '+str(s.get('f1',50))+'%,rgba(13,16,24,0) '+str(s.get('f2',72))+'%)'
        left=f'left:{s["pad"]}px;right:{s["pad"]}px;bottom:{s.get("pb",s["pad"])}px;top:auto;justify-content:flex-end'
    brand_css=f'position:absolute;top:{s.get("bt",s["pad"])}px;left:{s["pad"]}px;z-index:3' if kind!='wide' else ''
    topfade=f'<div class="topfade" style="height:{s.get("th",330)}px"></div>' if kind!='wide' else ''
    brand=f'<div class="brand" style="font-size:{s["bf"]}px;{brand_css}"><span style="width:{s["bl"]}px;height:{s["bl"]}px;display:block">{logo}</span>lrvdlinden.app</div>'
    chips=''.join(f'<span>{c}</span>' for c in t['chips']) if s.get('chips',True) else ''
    cta=f'<div class="cta" style="font-size:{s["cf"]}px">{t["cta"]} → lrvdlinden.app</div>' if s.get('cta',True) else ''
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>{ff}
html,body{{margin:0;width:{w}px;height:{h}px;overflow:hidden}}
body{{background:#0D1018;color:#E9ECF4;font-family:"Hanken Grotesk",sans-serif;position:relative}}
.glow{{position:absolute;inset:0;background:radial-gradient({int(w*.6)}px {int(h*.8)}px at {85 if kind=='wide' else 70}% {40 if kind=='wide' else 10}%,rgba(76,107,255,.38),transparent 70%),radial-gradient({int(w*.45)}px {int(h*.6)}px at 0% 100%,rgba(76,107,255,.16),transparent 70%)}}
.grid{{position:absolute;display:grid;gap:{int(ic*.17)}px;transform:rotate(-12deg);{grid}}}
.ic{{width:{ic}px;height:{ic}px;border-radius:{int(ic*.23)}px;overflow:hidden;background:#1D2333;box-shadow:0 18px 40px -12px rgba(0,0,0,.6)}}
.ic img{{width:100%;height:100%;object-fit:cover;display:block}}
.fade{{position:absolute;inset:0;background:{fade}}}
.topfade{{position:absolute;left:0;right:0;top:0;background:linear-gradient(180deg,#0D1018 0%,#0D1018 52%,rgba(13,16,24,0) 100%)}}
.left{{position:absolute;display:flex;flex-direction:column;{left};z-index:2}}
.brand{{display:flex;align-items:center;gap:{int(s['bl']*.25)}px;font-family:"Bricolage Grotesque";font-weight:700;letter-spacing:-.01em}}
.brand svg{{width:100%;height:100%}}
h1{{font:800 {s['hf']}px/1.0 "Bricolage Grotesque";letter-spacing:-.035em;margin:{s.get('hm','0 0 '+str(int(s['hf']*.32))+'px')}}}
h1 em{{font-style:normal;color:#8A9DFF}}
p{{margin:0;font-size:{s['sf']}px;color:#98A0B3;font-weight:500}}
.chips{{display:flex;gap:{int(s['sf']*.4)}px;margin-top:{int(s['sf']*1.05)}px;flex-wrap:wrap}}
.chips span{{font-weight:600;font-size:{int(s['sf']*.78)}px;padding:{int(s['sf']*.32)}px {int(s['sf']*.65)}px;border-radius:99px;border:1.5px solid #2E3650;color:#C9CFDD}}
.cta{{margin-top:{int(s['cf']*1.2)}px;align-self:flex-start;background:#4C6BFF;color:#fff;font-weight:600;padding:{int(s['cf']*.55)}px {int(s['cf']*1.1)}px;border-radius:99px}}
</style></head><body><div class="glow"></div><div class="grid">{cells}</div><div class="fade"></div>{topfade}
{brand if kind!='wide' else ''}
<div class="left">{brand if kind=='wide' else ''}<div style="display:flex;flex-direction:column">{'<div style="height:'+str(s.get('gap',0))+'px"></div>'}<h1>{t['h']}</h1><p>{t['sub']}</p>{'<div class="chips">'+chips+'</div>' if chips else ''}{cta}</div></div>
</body></html>'''
SPECS={
 'og-image-1200x630':(1200,630,'wide',dict(pad=64,tw=560,hf=62,sf=23,bf=30,bl=60,cf=20,cta=False)),
 'linkedin-post-1200x627':(1200,627,'wide',dict(pad=64,tw=560,hf=58,sf=22,bf=28,bl=56,cf=21,chips=False)),
 'x-bluesky-1600x900':(1600,900,'wide',dict(pad=90,tw=740,hf=84,sf=30,bf=38,bl=78,cf=28,ic=170,gr=-90,gt=-80,chips=False)),
 'facebook-cover-1640x624':(1640,624,'wide',dict(pad=150,pt=70,pb=70,tw=720,hf=62,sf=24,bf=28,bl=56,cf=21,chips=False,f1=52,f2=72)),
 'linkedin-cover-1584x396':(1584,396,'wide',dict(pad=420,pt=60,pb=60,tw=760,hf=48,sf=21,bf=24,bl=46,cf=18,cta=False,chips=False,ic=110,gr=-60,gt=-90,f1=60,f2=80,jc='center',gap=14)),
 'instagram-post-1080x1080':(1080,1080,'tall',dict(pad=80,pb=84,hf=86,sf=28,bf=34,bl=74,cf=24,th=330,gt=40,cta=False)),
 'instagram-post-1080x1350':(1080,1350,'tall',dict(pad=80,pb=96,hf=92,sf=30,bf=36,bl=78,cf=26,th=340,gt=60,ic=160,f1=42,f2=64)),
 'story-reels-1080x1920':(1080,1920,'tall',dict(pad=90,bt=260,pb=330,hf=96,sf=34,bf=40,bl=86,cf=30,th=560,ic=190,cols=5,f1=50,f2=66,gt=300)),
}
os.makedirs(OUT,exist_ok=True)
jobs=[]
for lang in ('nl','en'):
    for name,(w,h,kind,s) in SPECS.items():
        s=dict(s)
        if lang=='en': s['hf']=int(s['hf']*(.86 if kind=='wide' else .84))
        f=f'{OUT}/{lang}-{name}.html'; open(f,'w').write(page(w,h,lang,kind,s)); jobs.append([f,w,h,f'{OUT}/{lang}/{name}.png'])
json.dump(jobs,open(f'{OUT}/jobs.json','w'))
