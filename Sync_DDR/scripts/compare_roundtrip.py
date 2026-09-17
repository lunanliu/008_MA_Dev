#!/usr/bin/env python3
"""Compare a real Host export against the bundled 604-point transport fixture."""
import argparse, json, struct, sys
from pathlib import Path

def read_words(path):
    if path.suffix.lower() == '.bin':
        data = path.read_bytes()
        if len(data) % 4:
            raise ValueError('Binary file length is not a multiple of 4 bytes')
        return list(struct.unpack('<' + str(len(data)//4) + 'I', data))
    rows = path.read_text(encoding='utf-8-sig').splitlines()
    words = []
    for index, row in enumerate(rows):
        row = row.strip()
        if not row:
            continue
        if ',' in row or '\t' in row:
            raise ValueError('Use one decimal U32 per line, no header: line ' + str(index+1))
        value = int(row, 10)
        if not 0 <= value <= 0xFFFFFFFF:
            raise ValueError('Out-of-range U32 at line ' + str(index+1))
        words.append(value)
    return words

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('received', type=Path)
parser.add_argument('--expected', type=Path, default=Path(__file__).resolve().parents[1]/'examples/roundtrip_604/expected_u32.csv')
a = parser.parse_args()
try:
    got, expected = read_words(a.received), read_words(a.expected)
    mismatches = [i for i in range(min(len(got),len(expected))) if got[i] != expected[i]]
    first = mismatches[0] if mismatches else min(len(got),len(expected)) if len(got) != len(expected) else None
    ok = len(got) == len(expected) and not mismatches
    result = {'status': 'PASS' if ok else 'FAIL', 'received_count': len(got), 'expected_count': len(expected), 'value_mismatches': len(mismatches), 'missing_or_extra_count': abs(len(got)-len(expected)), 'first_error_index_zero_based': first}
    if first is not None:
        result['expected_at_first'] = expected[first] if first < len(expected) else None
        result['received_at_first'] = got[first] if first < len(got) else None
    print(json.dumps(result, indent=2))
    sys.exit(0 if ok else 1)
except (OSError, ValueError) as e:
    print(json.dumps({'status':'ERROR','message':str(e)}, indent=2))
    sys.exit(2)
