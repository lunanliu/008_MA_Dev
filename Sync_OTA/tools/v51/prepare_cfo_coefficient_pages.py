"""Derive/check the two coefficient ROM pages. Static file check, no RTL execution."""
from pathlib import Path
import argparse, hashlib, json

ROOT = Path(__file__).resolve().parents[2]
PAGE = 32768
COUNT = 74 * 820
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--write', action='store_true', help='Regenerate the two derived page files only')
p.add_argument('--output', type=Path, help='Optional static evidence JSON')
a = p.parse_args()
canonical = ROOT / 'ip/cfo/front2048_coefficient_index.mem'
values = [int(x, 16) for x in canonical.read_text().split()]
if len(values) != COUNT or any(x < 0 or x > 7 for x in values):
    raise ValueError('Canonical coefficient index must contain exactly 60680 three-bit entries')
padded = values + [0] * (2 * PAGE - COUNT)
rows = []
for page in range(2):
    path = ROOT / f'ip/cfo/front2048_coefficient_page{page}.mem'
    expected = padded[page * PAGE:(page + 1) * PAGE]
    if a.write:
        path.write_text(''.join(f'{x:x}\n' for x in expected), encoding='ascii', newline='\n')
    actual = [int(x, 16) for x in path.read_text().split()]
    if actual != expected:
        raise ValueError(f'{path.name}: content/length does not match canonical address mapping')
    rows.append({'path':path.relative_to(ROOT).as_posix(), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                 'entries':len(actual), 'valid_entries':min(PAGE, COUNT - page * PAGE)})
result = {'kind':'STATIC_COEFFICIENT_FILE_IDENTITY_NOT_RTL_SIMULATION',
          'canonical_path':canonical.relative_to(ROOT).as_posix(),
          'canonical_sha256':hashlib.sha256(canonical.read_bytes()).hexdigest(),
          'valid_entries_compared':COUNT, 'mismatches':0, 'padding_entries':2 * PAGE - COUNT,
          'pages':rows, 'boundary':{'last_page0_address':32767,'first_page1_address':32768,
                                   'window_zero_based':39,'first_page1_pilot_zero_based':788}}
if a.output:
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result,indent=2)+'\n', encoding='utf-8')
print(json.dumps(result,indent=2))
