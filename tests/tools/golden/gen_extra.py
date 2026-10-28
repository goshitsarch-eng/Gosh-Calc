import random, json, struct, sys
random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 99)
out = sys.argv[2] if len(sys.argv) > 2 else 'data/extra.jsonl'
def bits(v): return '%016x' % struct.unpack('<Q', struct.pack('<d', v))[0]
MODES = ['Standard','Scientific','Programmer']
reqs = []
# long histories: >100 completed evaluations, mixed ops and repeat-equals
for _ in range(60):
    seq = [] if random.random() < .6 else ['MODE:'+random.choice(MODES)]
    for i in range(random.randint(95, 140)):
        seq += ['D%d' % random.randint(1,9), 'BIN:'+random.choice(['Add','Sub','Mul']), 'D%d' % random.randint(1,9), 'EQ']
        if random.random() < .3: seq.append('EQ')
        if random.random() < .1: seq.append('RECALL:%d' % random.randint(0,99))
        if random.random() < .05: seq.append('ANS')
    seq += ['THIST', 'RECALL:99', 'RECALL:100', 'ANS', 'CLRH', 'ANS']
    reqs.append({'seq': seq})
# preloaded histories at/over the cap
for n in (98, 99, 100, 101, 105, 150):
    hist = [['e%d' % i, str(i), 'F:'+bits(float(i))] for i in range(n)]
    reqs.append({'seq': ['RECALL:%d' % (n-1), 'EQ', 'D1', 'BIN:Add', 'D1', 'EQ', 'RECALL:99', 'RECALL:100', 'ANS'], 'history': hist})
    reqs.append({'seq': ['MODE:Programmer', 'RECALL:97', 'D5', 'BIN:Mul', 'ANS', 'EQ', 'EQ', 'CLRH'], 'history': hist})
# token cap and nesting
for depth in (50, 100, 127, 128, 129, 130, 200, 300, 1000):
    reqs.append({'seq': ['MODE:Scientific'] + ['LP']*depth + ['D7', 'BIN:Add', 'D1'] + ['RP']*min(depth, 60) + ['EQ', 'D3', 'EQ']})
    reqs.append({'seq': ['MODE:Programmer'] + ['LP']*depth + ['D7', 'EQ']})
for n in (100, 126, 127, 128, 129, 200, 253, 254, 255, 256, 300):
    reqs.append({'seq': sum([['D1', 'BIN:Add'] for _ in range(n)], []) + ['D2', 'EQ', 'D4']})
    reqs.append({'seq': ['MODE:Scientific'] + sum([['D2', 'BIN:Pow'] for _ in range(n)], []) + ['D1', 'EQ']})
    reqs.append({'seq': ['MODE:Scientific'] + sum([['LP', 'D2', 'BIN:Add'] for _ in range(n//2)], []) + ['D1', 'EQ']})
# 32-char entry limit and overflow edges per mode/base
big = ['D9']*40
reqs.append({'seq': big + ['EQ', 'SIGN', 'BIN:Mul'] + big + ['EQ']})
for b in ('Hex', 'Oct', 'Bin', 'Dec'):
    reqs.append({'seq': ['MODE:Programmer', 'BASE:'+b] + ['D1']*70 + ['EQ', 'SIGN', 'UN:Not', 'BASE:Dec', 'BASE:Hex', 'BASE:Bin', 'BASE:Oct']})
    reqs.append({'seq': ['MODE:Programmer', 'BASE:'+b, 'D1', 'D0', 'BIN:Shl'] + ['D1', 'D5'] + ['EQ', 'BIN:Shr', 'D1', 'D0', 'EQ', 'BIN:Pow', 'D9', 'EQ']})
# i64 boundaries via decimal entry
for lit in ('9223372036854775807', '9223372036854775808', '-9223372036854775808', '9223372036854775806', '18446744073709551615'):
    d = ['D%s' % c for c in lit.lstrip('-')]
    pre = ['SIGN'] if lit.startswith('-') else []
    for op in ('Add', 'Sub', 'Mul', 'Div', 'Mod', 'Pow', 'YRoot', 'And', 'Shl'):
        reqs.append({'seq': ['MODE:Programmer'] + d + pre + ['BIN:'+op, 'D1', 'EQ', 'SIGN', 'UN:Not']})
        reqs.append({'seq': ['MODE:Programmer'] + d + pre + ['BIN:'+op, 'D1', 'SIGN', 'EQ']})
        reqs.append({'seq': ['MODE:Programmer'] + d + pre + ['BIN:'+op] + d + pre + ['EQ', 'EQ']})
    reqs.append({'seq': ['MODE:Programmer', 'BASE:Hex'] + [('D%d' % random.randint(0,15)) for _ in range(16)] + ['SIGN', 'BASE:Dec', 'SIGN', 'EQ', 'BIN:Add', 'D1', 'EQ']})
# float edges: huge/small, EE combos, trig near-zero snaps, factorial range
for x in ('0', '170', '171', '169', '1', '2.5', '-1', '1e308', '3e5', '89', '90', '180', '270', '360', '45', '0.5', '1e15', '1e16', '123456789012345', '12345678901234567890'):
    digits = []
    for ch in x:
        digits.append('DOT' if ch == '.' else ('EE' if ch == 'e' else ('SIGN' if ch == '-' else 'D'+ch)))
    # '-' sign must come after digits: reorder
    neg = x.startswith('-')
    body = []
    for ch in x.lstrip('-'):
        body.append('DOT' if ch == '.' else ('EE' if ch == 'e' else 'D'+ch))
    for un in ('Square','Cube','Sqrt','Cbrt','Recip','Fact','Sin','Cos','Tan','Asin','Acos','Atan','Ln','Log10','Exp','Pow10','Abs'):
        for ang in (False, True):
            reqs.append({'seq': ['MODE:Scientific'] + (['ANGLE'] if ang else []) + body + (['SIGN'] if neg else []) + ['UN:'+un, 'UN:'+un]})
with open(out, 'w') as f:
    for r in reqs: f.write(json.dumps(r)+'\n')
print(len(reqs), 'extra requests')
