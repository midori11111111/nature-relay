#!/usr/bin/env python3
"""Rebuild the bundled vector companions; rasterize with bundled sharp separately.
Twemoji 14.0.2 portions: CC BY 4.0; see LICENSE-GRAPHICS and sources.json.
Manual changes are documented in the app's character-asset-credits.json.
"""
from pathlib import Path
import json, math, re
ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'Adaptations'
OUT.mkdir(exist_ok=True)

def face(x=100,y=99,s=1):
 return f'''<g transform="translate({x} {y}) scale({s})"><ellipse cx="-12" cy="-3" rx="3" ry="4" fill="#273D30"/><ellipse cx="12" cy="-3" rx="3" ry="4" fill="#273D30"/><ellipse cx="-21" cy="7" rx="7" ry="3.5" fill="#FFB1A8"/><ellipse cx="21" cy="7" rx="7" ry="3.5" fill="#FFB1A8"/><path d="M-4 7 Q0 13 4 7" fill="none" stroke="#273D30" stroke-width="2.4" stroke-linecap="round"/></g>'''

def wrap(body, box='0 0 200 200'):
 return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{box}"><defs><filter id="sticker" x="-30%" y="-30%" width="160%" height="160%"><feMorphology in="SourceAlpha" operator="dilate" radius="3.6" result="edge"/><feFlood flood-color="white"/><feComposite in2="edge" operator="in"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs><g filter="url(#sticker)">{body}</g></svg>'''

def write(name, body): (OUT/f'{name}.svg').write_text(wrap(body))

def leaf(x,y,angle=0,scale=1,color='#77B255'):
 return f'<path transform="translate({x} {y}) rotate({angle}) scale({scale})" d="M0 0 Q-28 -28 0 -54 Q28 -28 0 0" fill="{color}"/>'

def stem():
 # The paired leaves and stem are retained from the inspected Twemoji blossom vector.
 src=(ROOT/'Originals'/'blossom.svg').read_text()
 part=re.search(r'<path fill="#77B255".*?/>',src).group(0)
 return '<g transform="translate(0 0) scale(5.5556)">'+part+'</g>'

# Each adapted stock character remains a general type character.
stock_faces={'sunflower':(18,18,0.15),'blossom':(18,13,0.13),'tree':(18,20,0.18),'conifer':(18,23,0.15),'cactus':(18,21,0.14),'rose':(18,14,0.15)}
for source in sorted((ROOT/'Originals').glob('*.svg')):
 body=re.sub(r'^.*?<svg[^>]*>|</svg>\s*$','',source.read_text(),flags=re.S)
 if source.stem in stock_faces:
  x,y,s=stock_faces[source.stem]
  body+=face(x,y,s)
 # Source vectors keep their geometry and receive only whitespace/white sticker edge.
 (OUT/f'twemoji-{source.stem}.svg').write_text(wrap(body,'-4 -4 44 44').replace('radius="3.6"','radius="0.7"'))

# A small set of deliberately species-informed plant companions.
# These remain stylized and are never a replacement for the real observation photo.
write('california-poppy',stem()+'''<path d="M47 62 Q30 25 72 35 Q99 4 124 35 Q166 25 153 64 L137 103 Q100 140 63 103Z" fill="#FFAC33"/><path d="M49 58 Q85 40 101 71 Q118 42 153 58 Q146 111 101 123 Q54 110 49 58" fill="#F4900C"/><path d="M67 48 Q76 28 94 35 Q85 59 94 72" fill="#FFD164"/>'''+face(101,90,.9))
write('fire-poppy',stem()+'''<path d="M46 58 Q38 24 78 36 Q103 14 124 38 Q162 31 153 65 Q157 114 101 124 Q45 108 46 58" fill="#E87842"/><path d="M53 60 Q85 45 101 74 Q119 45 148 61 Q145 112 101 120 Q58 108 53 60" fill="#F8A257"/>'''+face(101,89,.88))
# Stock stem plus separate three-petal bloom, with the central marks of a mariposa lily.
write('mariposa-lily',stem()+'''<path d="M100 94 Q47 99 43 57 Q48 23 76 37Z" fill="#F7E4D3"/><path d="M100 94 Q153 99 157 57 Q152 23 124 37Z" fill="#FFF0E6"/><path d="M100 97 Q69 40 100 18 Q131 40 100 97" fill="#FFF6ED"/><path d="M63 64 Q80 68 90 89 M137 64 Q120 68 110 89 M100 48 L100 78" fill="none" stroke="#BD7680" stroke-width="7" stroke-linecap="round"/><ellipse cx="100" cy="94" rx="27" ry="23" fill="#F8CE6C"/>'''+face(100,95,.75))
# A five-petal rose rather than a closed florists' rose.
rose=''
for i in range(5):
 a=i*72; rose+=f'<ellipse cx="100" cy="57" rx="30" ry="36" fill="{["#F5A3B9","#F29FB5","#F7B6C7","#F29FB5","#F5A3B9"][i]}" transform="rotate({a} 100 85)"/>'
write('california-wild-rose',stem()+rose+'<circle cx="100" cy="85" r="28" fill="#FFCA60"/>'+face(100,85,.8))
# Star flowers on a blue dicks stalk; deliberately distinct from a daisy.
cluster='<path d="M100 95 L100 180" stroke="#77B255" stroke-width="8" stroke-linecap="round"/>'+leaf(97,167,-65,.7)+leaf(102,151,60,.6)
for x,y,s in [(65,67,.75),(100,43,.85),(135,67,.75),(84,96,.7),(119,96,.7)]:
 petals=''
 for a in range(0,360,60): petals+=f'<ellipse cx="0" cy="-15" rx="8" ry="17" fill="#8589D8" transform="rotate({a})"/>'
 cluster+=f'<g transform="translate({x} {y}) scale({s})">{petals}<circle r="8" fill="#F9D36C"/></g>'
write('blue-dicks',cluster+'<ellipse cx="100" cy="111" rx="28" ry="22" fill="#9FA7E8"/>'+face(100,112,.7))
# Tubular coral flowers and narrow leaves for California fuchsia.
fuchsia='<path d="M94 175 Q119 114 95 54 M106 122 L64 94 M105 104 L143 70" fill="none" stroke="#77B255" stroke-width="7" stroke-linecap="round"/>'
for x,y,a in [(96,157,-55),(109,140,55),(91,113,-55),(113,108,55),(98,82,-50)]: fuchsia+=leaf(x,y,a,.55)
for x,y,a in [(90,39,-12),(50,76,-45),(144,51,30)]: fuchsia+=f'<g transform="translate({x} {y}) rotate({a})"><path d="M-10 2 Q-10 27 0 34 Q10 27 10 2 L17 -6 L5 -2 L0 -13 L-5 -2 L-17 -6Z" fill="#ED654B"/><path d="M-3 35 L-3 45 M4 35 L4 47" stroke="#E23B39" stroke-width="2.5" stroke-linecap="round"/></g>'
write('california-fuchsia',fuchsia+'<ellipse cx="106" cy="130" rx="22" ry="25" fill="#A6C982"/>'+face(106,129,.62))
# Three broad white petals and three green leaves for a Pacific trillium.
trillium='<path d="M100 98 L100 177" stroke="#6D9B4D" stroke-width="8" stroke-linecap="round"/>'
for a in (0,120,240):trillium+=f'<path d="M100 119 Q55 101 43 135 Q77 166 100 119" fill="#77B255" transform="rotate({a} 100 119)"/>'
for a in (0,120,240):trillium+=f'<path d="M100 89 Q67 54 100 19 Q133 54 100 89" fill="#F9F5E9" transform="rotate({a} 100 89)"/>'
write('pacific-trillium',trillium+'<circle cx="100" cy="89" r="24" fill="#F9D36C"/>'+face(100,89,.65))
# Simple lobed leaves, broad crown and small acorn cue: an oak-type character.
oak='''<path d="M89 99 L111 99 L121 177 Q101 184 81 177Z" fill="#9E6B43"/><path d="M96 131 L72 108 M104 121 L130 98" stroke="#9E6B43" stroke-width="12" stroke-linecap="round"/><path d="M46 125 Q17 120 29 91 Q17 68 42 58 Q37 27 69 32 Q87 9 109 29 Q138 13 152 40 Q180 41 173 69 Q192 92 168 111 Q169 140 139 137 Q117 153 96 137 Q63 149 46 125" fill="#77A95A"/><path d="M50 67 Q62 42 81 50 M132 47 Q151 48 154 67" fill="none" stroke="#96BE75" stroke-width="9" stroke-linecap="round"/><ellipse cx="151" cy="153" rx="12" ry="15" fill="#C89959"/><path d="M136 150 Q150 136 166 150 L166 154 L136 154Z" fill="#78563B"/><path d="M152 141 L154 135" stroke="#78563B" stroke-width="3" stroke-linecap="round"/>'''
write('oak',oak+face(100,102,.95))
# Fern morphology: paired small leaflets along an arching frond.
fern='<path d="M94 180 Q86 101 111 31" stroke="#4A7F43" stroke-width="7" fill="none" stroke-linecap="round"/>'
for i in range(7):
 y=55+i*16; x=103-(i*1.8); span=12+i*3
 fern+=f'<path d="M{x} {y} Q{x-span-14} {y-31} {x-span} {y-4} Q{x-8} {y+5} {x} {y}" fill="#77B255"/><path d="M{x} {y} Q{x+span+18} {y-30} {x+span+5} {y-3} Q{x+8} {y+7} {x} {y}" fill="#91BF69"/>'
write('fern',fern+'<ellipse cx="98" cy="154" rx="23" ry="21" fill="#A2C579"/>'+face(98,154,.65))
# Moss is a low cushion, grass a slender tuft, and stonecrop a fleshy rosette.
moss='<path d="M29 143 Q16 121 39 111 Q31 83 57 84 Q69 59 91 78 Q112 51 131 76 Q158 62 165 92 Q192 100 175 122 Q193 145 168 155 Q99 177 35 156Z" fill="#77A85A"/>'
for x,y in [(50,111),(80,92),(121,98),(152,122),(70,141)]: moss+=f'<path d="M{x} {y+9} L{x} {y-4} M{x} {y+3} L{x-6} {y-2} M{x} {y+3} L{x+6} {y-2}" stroke="#A6CA76" stroke-width="4" stroke-linecap="round"/>'
write('moss',moss+face(107,129,.9))
grass=''
for x,y,a,s in [(62,174,-20,2.2),(87,177,-8,2.6),(109,177,12,2.8),(133,173,30,2.2),(102,177,0,2.4)]:grass+=leaf(x,y,a,s,'#77A956')
write('grass',grass+'<ellipse cx="100" cy="151" rx="28" ry="24" fill="#A2C66E"/>'+face(100,152,.8))
rosette=''
for i in range(8): rosette+=f'<ellipse cx="100" cy="63" rx="21" ry="44" fill="{["#7EAA88","#9FC2A2"][i%2]}" transform="rotate({i*45} 100 105)"/>'
for i in range(6): rosette+=f'<ellipse cx="100" cy="81" rx="17" ry="30" fill="#B5CFAB" transform="rotate({i*60} 100 105)"/>'
write('stonecrop',rosette+'<circle cx="100" cy="105" r="28" fill="#C2D9B2"/>'+face(100,106,.8))
yucca='<path d="M100 145 L100 27" stroke="#74904A" stroke-width="6"/>'
for y,side in [(32,-1),(43,1),(56,-1),(69,1),(82,-1)]:yucca+=f'<ellipse cx="{100+side*10}" cy="{y}" rx="8" ry="12" fill="#F3EACC"/>'
for x,a in [(83,-65),(87,-40),(93,-20),(100,0),(107,20),(113,40),(117,65)]:yucca+=f'<path d="M100 177 Q{x-12} 131 {100+math.sin(math.radians(a))*80:.1f} {100-math.cos(math.radians(a))*23:.1f} L100 177" fill="#7D9E5C"/>'
write('yucca',yucca+'<ellipse cx="100" cy="153" rx="22" ry="25" fill="#9AB56C"/>'+face(100,154,.62))
barrel='''<ellipse cx="100" cy="114" rx="53" ry="64" fill="#77A956"/><path d="M100 52 Q77 111 100 177 M100 52 Q123 111 100 177 M75 60 Q49 119 77 168 M125 60 Q151 119 123 168" fill="none" stroke="#9FC279" stroke-width="5"/><path d="M55 93 L44 88 M48 120 L37 121 M57 148 L47 155 M145 93 L156 88 M152 120 L163 121 M143 148 L153 155" stroke="#DCCA8E" stroke-width="3" stroke-linecap="round"/>'''
for a in range(0,360,60):barrel+=f'<ellipse cx="100" cy="43" rx="10" ry="16" fill="#F4B552" transform="rotate({a} 100 55)"/>'
write('barrel-cactus',barrel+face(100,117,.9))
manzanita='''<path d="M99 177 L103 117 L69 79 M103 126 L139 86 M101 104 L104 67" stroke="#AC6651" stroke-width="13" fill="none" stroke-linecap="round"/>'''
for x,y in [(60,70),(90,54),(122,61),(146,80),(80,99),(124,107)]:manzanita+=f'<ellipse cx="{x}" cy="{y}" rx="25" ry="30" fill="#8DB280"/>'
manzanita+='<circle cx="144" cy="114" r="7" fill="#CF8A74"/><circle cx="157" cy="104" r="6" fill="#CF8A74"/>'
write('manzanita',manzanita+face(100,95,.85))
# Blue/purple spires, a shape cue for a lupine rather than the round daisy fallback.
lupine='<path d="M100 179 L100 32" stroke="#77B255" stroke-width="7"/>'
for i in range(7):
 y=39+i*14;w=9+i*1.5
 lupine+=f'<ellipse cx="{100-w/2}" cy="{y}" rx="{w}" ry="9" fill="#8D8DD5"/><ellipse cx="{100+w/2}" cy="{y+3}" rx="{w}" ry="9" fill="#ADA9E6"/>'
for a in (-70,-35,0,35,70):lupine+=leaf(100,177,a,.75)
write('miniature-lupine',lupine+'<ellipse cx="100" cy="114" rx="25" ry="22" fill="#AAA4E3"/>'+face(100,114,.7))
# Small white blossoms above the distinctive round, pierced leaf of miner's lettuce.
lettuce='<path d="M100 178 L100 52" stroke="#77B255" stroke-width="7"/><ellipse cx="100" cy="126" rx="60" ry="35" fill="#91BD68"/><ellipse cx="100" cy="123" rx="7" ry="5" fill="#5E9144"/>'
for x,y in [(87,57),(109,50),(120,67)]:
 for a in range(0,360,72):lettuce+=f'<ellipse cx="{x}" cy="{y-6}" rx="4" ry="8" fill="#FFF8E7" transform="rotate({a} {x} {y})"/>'
 lettuce+=f'<circle cx="{x}" cy="{y}" r="3.5" fill="#FFD164"/>'
write('miners-lettuce',lettuce+face(100,136,.85))
# Broad butterfly color families; these do not claim species-accurate wing patterns.
butterfly=(OUT/'twemoji-butterfly.svg').read_text()
for name,dark,light in [('orange','#79513C','#EDA346'),('cream','#716F61','#F0E7B9'),('dark','#382F36','#9A6F59'),('yellow','#373D35','#F1D36C'),('red','#333B3D','#D86757')]:
 (OUT/f'butterfly-{name}.svg').write_text(butterfly.replace('#1C6399',dark).replace('#55ACEE',light))
# Recoloring stock's general bird silhouette conveys a broad bird type only.
bird=(OUT/'twemoji-bird.svg').read_text()
for name,body,wing in [('blue','#709DC0','#477295'),('black','#42494A','#252D2D'),('brown','#9D8C72','#706454'),('yellow','#D9BB5D','#9B945D'),('gray','#9EA9A5','#6F7E79')]:
 (OUT/f'bird-{name}.svg').write_text(bird.replace('#DD2E44',body).replace('#A0041E',wing))
bear=(OUT/'twemoji-bear.svg').read_text()
(OUT/'bear-dark.svg').write_text(bear.replace('#C1694F','#55524C').replace('#D99E82','#8B8473'))
# Slender leaves replace the broad leaf stock so the grass fallback reads as a tuft.
grass=''
for tipx,tipy,control,color in [(40,43,43,'#7CAB5A'),(68,22,67,'#8EBA66'),(96,16,100,'#77A956'),(133,28,135,'#9BC878'),(166,55,164,'#77A956')]:
 grass+=f'<path d="M100 179 Q{control-18} 114 {tipx} {tipy} Q{control+16} 118 100 179" fill="{color}"/>'
write('grass',grass+'<ellipse cx="100" cy="154" rx="25" ry="23" fill="#A2C66E"/>'+face(100,154,.7))
# Two original type silhouettes avoid a fox mask for coyote and a spiral shell for limpet.
canine='''<path d="M49 84 L47 23 Q71 26 81 61 M151 84 L153 23 Q129 26 119 61" fill="#8D9488"/><path d="M57 65 L56 37 L76 65 M143 65 L144 37 L124 65" fill="#D3B7A2"/><path d="M53 71 Q100 40 147 71 L158 127 Q140 170 100 179 Q60 170 42 127Z" fill="#9BA08E"/><path d="M44 117 Q62 101 79 124 Q100 142 121 124 Q138 101 156 117 Q149 161 100 178 Q51 161 44 117" fill="#E4D9BE"/><ellipse cx="76" cy="103" rx="5" ry="7" fill="#273D30"/><ellipse cx="124" cy="103" rx="5" ry="7" fill="#273D30"/><path d="M88 135 Q100 129 112 135 Q110 148 100 149 Q90 148 88 135" fill="#38443A"/><path d="M100 148 L100 157 M90 157 Q100 166 110 157" fill="none" stroke="#38443A" stroke-width="3" stroke-linecap="round"/>'''
write('canine',canine)
limpet='''<ellipse cx="100" cy="153" rx="75" ry="20" fill="#8E9B8E"/><path d="M29 147 Q43 86 98 49 Q146 84 171 147 Q100 174 29 147" fill="#CBB69A"/><path d="M98 55 L56 151 M98 55 L79 158 M98 55 L103 161 M98 55 L127 156 M98 55 L149 150" stroke="#AB9276" stroke-width="5" fill="none" stroke-linecap="round"/><ellipse cx="98" cy="63" rx="10" ry="7" fill="#776A59"/>'''
write('limpet',limpet+face(100,126,.8))
# Poppy leaves are deeply divided; avoid the generic paired broad leaf stock shape.
def poppy_stem():
 body='<path d="M101 120 L101 181" stroke="#77B255" stroke-width="7" stroke-linecap="round"/>'
 for x,y,side in [(101,156,-1),(101,166,1)]:
  endx=x+side*43;endy=y-27
  body+=f'<path d="M{x} {y} L{endx} {endy}" stroke="#77B255" stroke-width="4" stroke-linecap="round"/>'
  for i in range(1,4):
   px=x+side*i*10;py=y-i*6
   body+=f'<path d="M{px} {py} L{px+side*1} {py-13} M{px} {py} L{px+side*13} {py+2}" stroke="#77B255" stroke-width="4" stroke-linecap="round"/>'
 return body
for name in ('california-poppy','fire-poppy'):
 p=OUT/f'{name}.svg';p.write_text(p.read_text().replace(stem(),poppy_stem()))
