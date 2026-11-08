#!/usr/bin/env python3
"""기능 분류: 설치 창 배경을 1×·2×로 생성한다. 앱/폴더 아이콘은 Finder가 그린다."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'Resources/Installer'
FONT = '/System/Library/Fonts/AppleSDGothicNeo.ttc'
W, H, SCALE = 720, 460, 2
im = Image.new('RGB', (W*SCALE, H*SCALE))
pixels = im.load()
for y in range(H*SCALE):
    for x in range(W*SCALE):
        # 작은 민트 빛 번짐만 사용해 실제 아이콘과 설치 안내에 시선을 모은다.
        glow = math.exp(-(((x/SCALE-360)/290)**2 + ((y/SCALE-205)/185)**2)*2.1)
        pixels[x,y] = (round(8+4*glow), round(12+12*glow), round(18+12*glow))
d = ImageDraw.Draw(im)
def box(rect, **kwargs):
    rect=tuple(round(v*SCALE) for v in rect)
    if 'radius' in kwargs: kwargs['radius']*=SCALE
    if 'width' in kwargs: kwargs['width']*=SCALE
    d.rounded_rectangle(rect, **kwargs)
def text(s, x, y, size, fill, bold=False, anchor='left'):
    font=ImageFont.truetype(FONT, round(size*SCALE), index=6 if bold else 0)
    bounds=d.textbbox((0,0),s,font=font)
    if anchor=='center': x=x*SCALE-(bounds[2]-bounds[0])/2-bounds[0]
    elif anchor=='right': x=x*SCALE-(bounds[2]-bounds[0])-bounds[0]
    else: x=x*SCALE-bounds[0]
    d.text((x, y*SCALE-bounds[1]),s,font=font,fill=fill)
MINT='#91EDB5'; WHITE='#F3F7F8'; MUTED='#9AA9B4'
text('ZCRE 서포터',32,23,12,MINT,True)
text('macOS',688,25,10,'#73838F',anchor='right')
text('작업 곁에, 지크',360,60,29,WHITE,True,'center')
text('오른쪽 폴더로 옮기면 설치가 완료돼요',360,103,13,MUTED,anchor='center')
for x in (204,516):
    box((x-76,148,x+76,309),radius=22,fill='#121C24',outline='#26343E',width=1)
# Finder의 기본 검정 이름표가 그림 배경에서도 읽히도록 작은 밝은 받침을 둔다.
for x in (204,516):
    box((x-58,269,x+58,291),radius=9,fill='#E3EBE8')
# 두 Finder 아이콘 사이의 드래그 방향.
d.line([(325*SCALE,213*SCALE),(393*SCALE,213*SCALE)],fill=MINT,width=3*SCALE)
d.line([(382*SCALE,202*SCALE),(393*SCALE,213*SCALE),(382*SCALE,224*SCALE)],fill=MINT,width=3*SCALE,joint='curve')
text('드래그',360,238,10,'#81958F',anchor='center')
d.line([(48*SCALE,333*SCALE),(672*SCALE,333*SCALE)],fill='#24313A',width=SCALE)
for y,number,label in [(353,'1','앱을 Applications 폴더로 드래그'),(385,'2','Applications에서 ZCRE 서포터 실행')]:
    # 문구 중심을 창 중앙에 맞추고 번호는 왼쪽에 따로 배치한다.
    font=ImageFont.truetype(FONT,13*SCALE,index=0); b=d.textbbox((0,0),label,font=font)
    label_width=(b[2]-b[0])/SCALE
    start=(W-label_width)/2
    box((start-30,y-1,start-11,y+18),radius=7,fill='#1C362D')
    text(number,start-20.5,y+4.5,10,MINT,True,'center')
    text(label,W/2,y+2,13,'#D0DADF',anchor='center')
text('Apple 서명 · 공증 완료',32,435,10,'#7C9287')
text('Intel & Apple Silicon  ·  macOS 14+',688,435,10,'#71818D',anchor='right')
DEST.mkdir(parents=True,exist_ok=True)
im.save(DEST/'background@2x.png',dpi=(144,144))
im.resize((W,H),Image.Resampling.LANCZOS).save(DEST/'background.png',dpi=(72,72))
print('Installer background generated: 720×460 / 1440×920')
