import random, json, struct, sys
seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
n_seq = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
out = sys.argv[3] if len(sys.argv) > 3 else 'data/corpus.jsonl'
random.seed(seed)
BINS = ['Add','Sub','Mul','Div','Mod','Pow','YRoot','Shl','Shr','And','Or','Xor']
UNS = ['Square','Cube','Sqrt','Cbrt','Recip','Fact','Sin','Cos','Tan','Asin','Acos','Atan','Ln','Log10','Exp','Pow10','Not','Abs']
MODES = ['Standard','Scientific','Programmer']
BASES = ['Hex','Dec','Oct','Bin']
DIALOGS = ['Settings','About','Shortcuts']
THEMES = ['system','light','dark']
def bits(v): return '%016x' % struct.unpack('<Q', struct.pack('<d', v))[0]

def digits_run(maxlen=12):
    n = random.choice([1,1,2,2,3,4,5,6,8,10,12,16,20,30,33,34][:random.randint(6,16)])
    return ['D%d' % random.choice([random.randint(0,9)]*3 + [random.randint(0,15)]) for _ in range(n)]
def dec_digits(n): return ['D%d' % random.randint(0,9) for _ in range(n)]
def number():
    r = random.random()
    seq = dec_digits(random.choice([1,1,2,2,3,4,6,8,12,17,25,32,34]))
    if r < 0.25: seq += ['DOT'] + dec_digits(random.randint(0,6))
    elif r < 0.30: seq = ['DOT'] + dec_digits(random.randint(1,4))
    if random.random() < 0.08: seq += ['EE'] + (['SIGN'] if random.random() < 0.1 else []) + dec_digits(random.randint(0,3))
    if random.random() < 0.12: seq += ['SIGN']
    return seq
def hexnum():
    return ['D%d' % random.randint(0,15) for _ in range(random.choice([1,2,3,4,8,12,15,16,17]))]

def cmd_chaos(mode_hint=None):
    r = random.random()
    if r < 0.25: return 'D%d' % random.randint(0,15)
    if r < 0.33: return 'BIN:' + random.choice(BINS)
    if r < 0.40: return 'UN:' + random.choice(UNS)
    pool = ['DOT','PCT','EQ','EQ','BS','CE','CA','SIGN','ANGLE','LP','RP','ANS','EE','CONST:Pi','CONST:E','COPY','THIST','CLRH',
            'BASE:'+random.choice(BASES),'MODE:'+random.choice(MODES),'RECALL:%d' % random.randint(0,4),
            'DLG:'+random.choice(DIALOGS),'CLOSE','THEME:'+random.choice(THEMES),'DISMISS',
            'WIN:%s,%s,%d' % (random.choice([100,360,460,800,2400,5000,300.5]), random.choice([100,480,700,1600,9000]), random.randint(0,1))]
    return random.choice(pool)

def seq_calc():
    out = []
    mode = random.choice(MODES)
    if mode != 'Standard': out.append('MODE:'+mode)
    for _ in range(random.randint(1,6)):
        out += number()
        r = random.random()
        if r < 0.15 and mode == 'Scientific': out.append('UN:'+random.choice(UNS[:18]))
        elif r < 0.25 and mode != 'Programmer': out.append('UN:' + random.choice(['Square','Sqrt','Recip']))
        out.append('BIN:' + random.choice(BINS[:6] if mode != 'Programmer' else BINS))
        if random.random() < 0.1: out.append('BIN:' + random.choice(BINS))
        if random.random() < 0.1: out.append('PCT')
    out += number()
    out.append('EQ')
    for _ in range(random.randint(0,3)):
        r = random.random()
        if r < 0.4: out.append('EQ')
        elif r < 0.7: out += ['BIN:'+random.choice(BINS[:4]) ] + number() + ['EQ']
        elif r < 0.85: out.append('UN:'+random.choice(UNS))
        else: out.append(cmd_chaos())
    return out

def seq_chaos():
    return [cmd_chaos() for _ in range(random.randint(5,120))]

def seq_programmer():
    out = ['MODE:Programmer']
    for _ in range(random.randint(2,8)):
        if random.random() < 0.5: out.append('BASE:'+random.choice(BASES))
        out += hexnum() if random.random() < 0.6 else dec_digits(random.choice([1,3,8,12,18,19,20]))
        r = random.random()
        if r < 0.1: out.append('SIGN')
        if r > 0.9: out.append('UN:Not')
        out.append('BIN:'+random.choice(BINS))
        if random.random() < 0.3: out.append(random.choice(['LP','RP','PCT']))
    out += hexnum() + ['EQ']
    for _ in range(random.randint(0,4)):
        out.append(random.choice(['EQ','EQ','SIGN','UN:Not','BASE:'+random.choice(BASES),'ANS','RECALL:0','BS','CE',cmd_chaos()]))
    return out

def seq_sci():
    out = ['MODE:Scientific']
    depth = 0
    for _ in range(random.randint(2,12)):
        r = random.random()
        if r < 0.25: out.append('LP'); depth += 1
        out += number()
        if r > 0.8: out.append('UN:'+random.choice(UNS[:17]))
        if r > 0.9: out.append(random.choice(['CONST:Pi','CONST:E']))
        if random.random() < 0.3 and depth: out.append('RP'); depth -= 1
        out.append('BIN:'+random.choice(BINS[:6]))
        if random.random() < 0.1: out.append('PCT')
    out += number() + [random.choice(['EQ','EQ','RP','UN:'+random.choice(UNS[:17]),'PCT','EQ'])]
    if random.random() < 0.3: out.append('ANGLE')
    for _ in range(random.randint(0,3)):
        out.append(random.choice(['EQ','UN:'+random.choice(UNS[:17]),'ANS','ANGLE','EE','CE','CA',cmd_chaos()]))
    return out

def seq_unary_probe():
    # every unary on assorted inputs in each angle unit (the keypad's single-step functions)
    out = ['MODE:Scientific']
    if random.random() < 0.5: out.append('ANGLE')
    for _ in range(random.randint(3,10)):
        out += ['CA'] + number() + ['UN:'+random.choice(UNS[:17])]
        if random.random() < 0.4: out += ['UN:'+random.choice(UNS[:17])]
    return out

NASTY_HISTORY = [
    ['2 + 3','5',None], ['x','2.5',None], ['x','-7',None], ['x','abc',None], ['x','1e400',None], ['x','NaN',None], ['x','inf',None],
    ['x','π≈3.14159',None], ['x','é'*40,None], ['y','9'*500,None], ['z','',None], ['x','-',None],
    ['1 + 1','2','F:'+bits(2.0)], ['1/3','0.333333333333','F:'+bits(1/3)], ['big','1e300','F:'+bits(1e300)],
    ['ff','255','I:255'], ['neg','-1','I:-1'], ['max','9223372036854775807','I:9223372036854775807'],
    ['min','-9223372036854775808','I:-9223372036854775808'], ['frac','0.5','F:'+bits(0.5)], ['huge','9','F:'+bits(1.9e19)], ['neg0','0','F:'+bits(-0.0)],
]
def seq_history():
    hist = [list(random.choice(NASTY_HISTORY)) for _ in range(random.randint(1,6))]
    out = []
    if random.random() < 0.5: out.append('MODE:'+random.choice(MODES))
    if random.random() < 0.3: out.append('BASE:'+random.choice(BASES))
    for _ in range(random.randint(2,14)):
        out.append(random.choice(['RECALL:%d' % random.randint(0,6),'ANS','EQ','BIN:'+random.choice(BINS),'UN:'+random.choice(UNS),
                                  'MODE:'+random.choice(MODES),'BASE:'+random.choice(BASES),'D%d' % random.randint(0,9),'BS','SIGN','CLRH','CA','CE','THIST']))
    return out, hist

def seq_ui():
    return [random.choice(['THIST','DLG:Settings','DLG:About','DLG:Shortcuts','CLOSE','THEME:system','THEME:light','THEME:dark','THEME:dark','DISMISS','COPY','QUIT',
                            'WIN:460,700,0','WIN:460,700,0','WIN:800,900,1','WIN:100,100,0','WIN:9999,9999,0','WIN:%d,%d,0' % (random.randint(300,3000),random.randint(400,2000)),
                            'D5','EQ','BIN:Add','MODE:'+random.choice(MODES)]) for _ in range(random.randint(5,40))]

gens = [(seq_calc,30),(seq_chaos,20),(seq_programmer,15),(seq_sci,15),(seq_unary_probe,8),(seq_history,8),(seq_ui,4)]
total = sum(w for _,w in gens)
reqs = []
for i in range(n_seq):
    r = random.uniform(0,total); acc = 0
    for g,w in gens:
        acc += w
        if r <= acc: break
    res = g()
    if isinstance(res, tuple): seq, hist = res; reqs.append({'seq': seq, 'history': hist})
    else: reqs.append({'seq': res})
# keyboard probes
keys = [chr(c) for c in range(32,127)] + ['Enter','Escape','Delete','Backspace','Insert','F1','Tab','ArrowLeft','é','π','Shift','F2','Home']
for k in keys:
    for primary in (False, True):
        for alt in (False, True):
            for mode in MODES:
                for base in (['Dec','Hex'] if mode == 'Programmer' else ['Dec']):
                    reqs.append({'key': k, 'primary': primary, 'alt': alt, 'mode': mode, 'base': base})
with open(out,'w') as f:
    for r in reqs: f.write(json.dumps(r, ensure_ascii=False)+'\n')
print(len(reqs), 'requests')
