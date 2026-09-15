"""Read-only LINK010R1 XPM binding evidence checker. No native subprocesses.

run(simdir) returns JSON-compatible diagnostics. --self-check uses memory only.
Required files are compile.bat, the actual *_vlog.prj, xvlog.log, compile.log,
elaborate.log, and xsim.ini. xelab.log is checked too when present.
Source content/hash qualification belongs to the separately frozen source lock.
"""
from pathlib import Path
from collections import Counter
import argparse
import copy
import hashlib
import json
import ntpath
import re
import stat

ROOT = Path('D:/008_MA_Dev/T11_CFO')
SIMDIR = ROOT / 'vivado/CFO_LINK010R1/CFO_LINK010R1.sim/sim_1/behav/xsim'
PRJ = 'cfo_estimator_link_tb_vlog.prj'
REQUIRED = ('compile.bat', PRJ, 'xvlog.log', 'compile.log', 'elaborate.log', 'xsim.ini')
OPTIONAL = ('xelab.log',)
NAMES = ('xpm_cdc', 'xpm_memory', 'xpm_fifo')
MODULES = ('xpm_fifo_async', 'xpm_fifo_base', 'xpm_fifo_rst', 'xpm_cdc_async_rst',
           'xpm_cdc_sync_rst', 'xpm_cdc_single', 'xpm_memory_base')
MAX_FILE_BYTES = 16 * 1024 * 1024


def canonical(value, base=str(SIMDIR)):
    """Windows lexical absolute path; does not read the filesystem."""
    value = str(value).strip()
    if not value or any(c in value for c in ('$', '%', '\x00', '\r', '\n')):
        raise ValueError('empty, variable-dependent or invalid path')
    value = value.replace('/', '\\')
    drive, tail = ntpath.splitdrive(value)
    if value.startswith('\\\\') or (drive and not tail.startswith('\\')):
        raise ValueError('UNC/device or drive-relative path is not permitted')
    if tail.startswith('\\') and not drive:
        raise ValueError('root-relative path without drive is not permitted')
    return ntpath.normcase(ntpath.normpath(value if drive else ntpath.join(str(base), value)))


EXPECTED_SIMDIR = canonical(str(SIMDIR))
EXPECTED_VENDOR = {canonical(str(ROOT / f'sim/vendor/link010r1/{name}.sv')) for name in NAMES}


def inside(path, directory=EXPECTED_SIMDIR):
    try:
        return path != directory and ntpath.commonpath((path, directory)) == directory
    except ValueError:
        return False


def tokens(line):
    """Tokenize generated Windows commands/PRJ, preserving path backslashes."""
    pattern = re.compile(r'"[^"\r\n]*"|[^\s"]+')
    out = []
    end = 0
    for match in pattern.finditer(line):
        if line[end:match.start()].strip():
            raise ValueError('unbalanced or unsupported quoting')
        part = match.group()
        out.append(part[1:-1] if part.startswith('"') else part)
        end = match.end()
    if line[end:].strip():
        raise ValueError('unbalanced or unsupported quoting')
    return out


def logical_lines(text):
    pending = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            if pending:
                yield ' '.join(pending)
                pending = []
            continue
        continued = line.endswith('\\')
        pending.append(line[:-1].rstrip() if continued else line)
        if not continued:
            yield ' '.join(pending)
            pending = []
    if pending:
        yield ' '.join(pending)


def xpm_source(path):
    name = ntpath.basename(path).casefold()
    return name.startswith('xpm_') and ntpath.splitext(name)[1] in ('.sv', '.v', '.vhd', '.vhdl')


def parse_prj(text):
    rows = []
    for line in logical_lines(text):
        parts = tokens(line)
        if parts == ['nosort']:
            continue
        if len(parts) < 3 or parts[0].lower() not in ('sv', 'verilog', 'vhdl', 'vhdl2008'):
            raise ValueError('unrecognized PRJ record: ' + line[:140])
        language, library = parts[:2]
        pos = 2
        while pos < len(parts):
            item = parts[pos]
            if item in ('-i', '--include', '-d', '--define'):
                if pos + 1 == len(parts):
                    raise ValueError('missing PRJ option value')
                pos += 2
                continue
            if item.startswith('-'):
                raise ValueError('unsupported PRJ option: ' + item)
            path = canonical(item)
            rows.append({'path': path, 'library': library, 'language': language.lower()})
            pos += 1
    return rows


def parse_compile(text):
    commands = []
    for line in text.splitlines():
        line = line.strip().lstrip('@')
        if not line or re.match(r'(?i)^(?:rem|echo)(?:\s|$)', line) or line.startswith('::'):
            continue
        parts = tokens(line)
        if parts and parts[0].lower() == 'call':
            parts = parts[1:]
        if not parts:
            continue
        if parts[0].lower() in ('cd', 'chdir', 'pushd', 'popd'):
            raise ValueError('compile.bat changes working directory')
        if ntpath.basename(parts[0]).lower() not in ('xvlog', 'xvlog.exe', 'xvlog.bat'):
            continue
        if any(x in line for x in '&|<>'):
            raise ValueError('compound xvlog command is not permitted')
        if any(x.lower() in ('-f', '--file') for x in parts[1:]):
            raise ValueError('xvlog response file hides compilation inputs')
        indices = [i for i, item in enumerate(parts) if item.lower() == '-prj']
        if len(indices) != 1 or indices[0] + 1 >= len(parts):
            raise ValueError('xvlog must have exactly one explicit -prj')
        project = canonical(parts[indices[0] + 1])
        if project != canonical(PRJ):
            raise ValueError('xvlog -prj does not point to expected private project file')
        if any(ntpath.splitext(x)[1].lower() in ('.v', '.sv', '.vhd', '.vhdl') for x in parts[1:]):
            raise ValueError('extra HDL positional input outside -prj')
        commands.append({'line': line, 'project': project})
    if len(commands) != 1:
        raise ValueError('compile.bat must contain exactly one actual xvlog invocation; echo is not execution')
    return commands


def parse_analyzed(text):
    rows = []
    pattern = re.compile(r'Analyzing\s+(SystemVerilog|Verilog|VHDL)\s+file\s+"([^"]+)"\s+into\s+library\s+([A-Za-z0-9_]+)', re.I)
    for match in pattern.finditer(text):
        path = canonical(match[2])
        if xpm_source(path):
            rows.append({'path': path, 'library': match[3], 'language': match[1]})
    return rows


def parse_elaboration(text):
    commands = []
    for line in text.splitlines():
        match = re.match(r'^\s*Running:\s*(.*)$', line, re.I)
        if not match:
            continue
        parts = tokens(match[1])
        if not parts or ntpath.basename(parts[0]).lower() not in ('xelab', 'xelab.exe', 'xelab.bat'):
            continue
        libs = []
        for pos, item in enumerate(parts[1:], 1):
            if item.lower() in ('-f', '--file', '-prj', '-initfile', '--initfile'):
                raise ValueError('xelab hidden inputs or alternate ini not permitted: ' + item)
            if item in ('-L', '-l', '-lib', '--lib'):
                if pos + 1 >= len(parts):
                    raise ValueError('xelab library option missing value')
                lib = parts[pos + 1]
                if '=' in lib:
                    raise ValueError('xelab library-directory override bypasses audited ini')
                libs.append(lib)
        if 'cfo_xpm' not in libs:
            raise ValueError('actual xelab command lacks -L cfo_xpm')
        if any(lib.casefold() == 'xpm' for lib in libs[:libs.index('cfo_xpm')]):
            raise ValueError('actual xelab searches xpm before cfo_xpm')
        commands.append({'line': line, 'libraries': libs})
    if not commands:
        raise ValueError('actual Running: xelab command missing')
    units = [{'library': m[1], 'module': m[2]} for m in re.finditer(
        r'^\s*(?:INFO:\s*\[[^\]]+\]\s*)?Compiling\s+module\s+([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)(?=\W|$)', text, re.I | re.M)]
    return commands, units


def parse_mapping(text):
    entries = []
    for line in text.splitlines():
        if '=' not in line or line.lstrip().startswith(('#', ';')):
            continue
        key, value = line.split('=', 1)
        if key.strip().casefold() != 'cfo_xpm':
            continue
        if key.strip() != 'cfo_xpm':
            raise ValueError('cfo_xpm mapping has wrong logical-library case')
        value = value.strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        target = canonical(value)
        if not inside(target):
            raise ValueError('cfo_xpm mapping is not strictly inside the private simdir')
        entries.append({'line': line, 'target': target})
    if len(entries) != 1:
        raise ValueError('expected exactly one cfo_xpm mapping, found ' + str(len(entries)))
    return entries[0]


def check_documents(documents):
    """Pure in-memory content checks, separate from run() filesystem checks."""
    result = {'schema': 'link010r1_binding_v1', 'status': 'LINK010R1_BINDING_FAIL',
              'all_checks': False, 'native_started': False, 'checks': {}, 'errors': [], 'details': {}}
    def check(name, condition, error):
        result['checks'][name] = bool(condition)
        if not condition:
            result['errors'].append(name + ': ' + error)
    def parse(name, parser, text):
        try:
            value = parser(text)
            check(name, True, '')
            return value
        except (ValueError, IndexError) as exc:
            check(name, False, str(exc))
            return None
    for name in REQUIRED:
        check('nonempty_' + name, bool(documents.get(name, '').strip()), 'required evidence missing or empty')
    for name in OPTIONAL:
        if name in documents:
            check('nonempty_' + name, bool(documents[name].strip()), 'optional file exists but is empty')
    commands = parse('compile_command', parse_compile, documents.get('compile.bat', ''))
    result['details']['compile_commands'] = commands
    rows = parse('project_parse', parse_prj, documents.get(PRJ, ''))
    vendor = [row for row in rows or [] if xpm_source(row['path'])]
    expected_counts = Counter({path: 1 for path in EXPECTED_VENDOR})
    check('project_exact_private_xpm_sources', Counter(row['path'] for row in vendor) == expected_counts,
          'PRJ must contain each private XPM source exactly once and no other XPM HDL source')
    check('project_private_xpm_library', bool(vendor) and all(row['library'] == 'cfo_xpm' and row['language'] == 'sv' for row in vendor),
          'every private XPM PRJ source must be SystemVerilog in cfo_xpm')
    result['details']['project_vendor_sources'] = vendor
    analyzed = {}
    for name in ('xvlog.log', 'compile.log'):
        entries = parse('parse_' + name, parse_analyzed, documents.get(name, ''))
        entries = entries or []
        analyzed[name] = entries
        check('exact_private_sources_' + name, Counter(row['path'] for row in entries) == expected_counts,
              'analysis log must identify precisely the three private XPM sources once each')
        check('private_library_' + name, bool(entries) and all(row['library'] == 'cfo_xpm' for row in entries),
              'analysis log reports an XPM source outside cfo_xpm')
    result['details']['analyzed_vendor_sources'] = analyzed
    units = [];elab_commands = []
    for name in ('elaborate.log', 'xelab.log'):
        if name != 'elaborate.log' and name not in documents:
            continue
        parsed = parse('elaboration_' + name, parse_elaboration, documents.get(name, ''))
        if parsed:
            elab_commands.extend(parsed[0]);units.extend(parsed[1])
    bound = {name: any(row['library'] == 'cfo_xpm' and row['module'] == name for row in units) for name in MODULES}
    check('seven_private_xpm_modules', all(bound.values()), 'missing private elaborated modules: ' + ', '.join(name for name, yes in bound.items() if not yes))
    wrong = [row for row in units if row['library'].casefold() == 'xpm' or (row['module'].casefold().startswith('xpm_') and row['library'] != 'cfo_xpm')]
    check('no_other_xpm_binding', not wrong, 'XPM units bound outside private cfo_xpm: ' + repr(wrong))
    result['details'].update(elaboration_commands=elab_commands, expected_modules=bound, wrong_bindings=wrong)
    result['details']['mapping'] = parse('private_mapping', parse_mapping, documents.get('xsim.ini', ''))
    result['all_checks'] = bool(result['checks']) and all(result['checks'].values())
    if result['all_checks']:
        result['status'] = 'LINK010R1_BINDING_PASS'
    return result


def no_reparse(path):
    for item in (path, *path.parents):
        flags = item.lstat().st_file_attributes
        if flags & stat.FILE_ATTRIBUTE_REPARSE_POINT:
            raise ValueError('reparse point is not permitted: ' + str(item))


def run(simdir):
    """Read only exact new-project simulation evidence; never launches a tool."""
    documents = {};evidence = [];stamps = {};fs_errors = []
    try:
        if canonical(simdir) != EXPECTED_SIMDIR:
            raise ValueError('simdir must be exactly ' + str(SIMDIR))
        base = Path(simdir)
        if not base.is_dir() or canonical(str(base.resolve(strict=True))) != EXPECTED_SIMDIR:
            raise ValueError('private simdir missing or resolves to another location')
        no_reparse(base)
    except (OSError, ValueError, AttributeError) as exc:
        return {'schema': 'link010r1_binding_v1', 'status': 'LINK010R1_BINDING_FAIL', 'all_checks': False,
                'native_started': False, 'checks': {'exact_private_simdir': False}, 'errors': [str(exc)], 'details': {}, 'evidence': []}
    for name in REQUIRED + OPTIONAL:
        path = base / name
        try:
            if name in OPTIONAL and not path.exists():
                continue
            no_reparse(path)
            before = path.stat()
            if not path.is_file() or before.st_size <= 0 or before.st_size > MAX_FILE_BYTES:
                raise ValueError('not a nonempty regular file within 16 MiB bound')
            data = path.read_bytes()
            after = path.stat()
            stamp = (before.st_size, before.st_mtime_ns, before.st_ino)
            if (after.st_size, after.st_mtime_ns, after.st_ino) != stamp:
                raise ValueError('evidence changed while reading')
            documents[name] = data.decode('utf-8-sig')
            stamps[name] = stamp
            evidence.append({'name': name, 'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest().upper()})
        except (OSError, UnicodeError, ValueError, AttributeError) as exc:
            fs_errors.append(name + ': ' + str(exc))
    result = check_documents(documents)
    result['evidence'] = evidence
    result['simdir'] = str(base)
    result['checks']['exact_private_simdir'] = True
    mapping = result['details'].get('mapping')
    directory_ok = False
    if mapping:
        try:
            target = Path(mapping['target'])
            no_reparse(target)
            actual = canonical(str(target.resolve(strict=True)))
            directory_ok = target.is_dir() and inside(actual) and actual == mapping['target']
            if not directory_ok:
                raise ValueError('mapped library directory is missing or escapes private simdir')
            mapping['resolved_directory'] = str(target.resolve(strict=True))
        except (OSError, ValueError, AttributeError) as exc:
            fs_errors.append('mapped_library_directory: ' + str(exc))
    result['checks']['mapped_private_directory_exists'] = directory_ok
    if not directory_ok:
        fs_errors.append('mapped_private_directory_exists: no verified existing private library directory')
    for name in REQUIRED + OPTIONAL:
        try:
            path = base / name
            if (name in stamps) != path.exists():
                raise ValueError('evidence membership changed or unreadable evidence present')
            if name in stamps:
                item = path.stat()
                if (item.st_size, item.st_mtime_ns, item.st_ino) != stamps[name]:
                    raise ValueError('evidence changed during check')
        except (OSError, ValueError) as exc:
            fs_errors.append(name + ': ' + str(exc))
    result['checks']['filesystem_evidence_stable_and_readable'] = not fs_errors
    result['errors'].extend(fs_errors)
    result['all_checks'] = bool(result['checks']) and all(result['checks'].values()) and not result['errors']
    result['status'] = 'LINK010R1_BINDING_PASS' if result['all_checks'] else 'LINK010R1_BINDING_FAIL'
    return result


def self_check():
    """Synthetic documents in memory only; no fixture directories or native tools."""
    paths = sorted(EXPECTED_VENDOR)
    project = '# synthetic in-memory PRJ\nsv cfo_xpm -i "../../../../../../sim/vectors" \\\n' + ' \\\n'.join('"' + ntpath.relpath(p, EXPECTED_SIMDIR).replace('\\', '/') + '"' for p in paths) + '\nverilog cfo_xpm "glbl.v"\nnosort\n'
    analysis = '\n'.join('INFO: [VRFC 10-2263] Analyzing SystemVerilog file "' + p.replace('\\', '/') + '" into library cfo_xpm' for p in paths)
    elaborate = ('Vivado Simulator v2021.1\nRunning: C:/NIFPGA/programs/Vivado2021_1/bin/unwrapped/win64.o/xelab.exe -L cfo_xpm -L uvm -L xpm cfo_xpm.cfo_estimator_link_tb cfo_xpm.glbl\n' + '\n'.join('Compiling module cfo_xpm.' + name + '(SYNTHETIC=1)' for name in MODULES))
    fixture = {'compile.bat': '@echo off\necho "xvlog -prj ' + PRJ + '"\ncall xvlog --incr --relax -L uvm -prj ' + PRJ + ' -log xvlog.log\n', PRJ: project,
               'xvlog.log': analysis, 'compile.log': analysis, 'elaborate.log': elaborate, 'xsim.ini': 'xpm=C:/installed/xpm\ncfo_xpm=xsim.dir/cfo_xpm\n'}
    outcomes = []
    def trial(name, docs, expected):
        observed = check_documents(docs)
        outcomes.append({'name': name, 'expected_pass': expected, 'observed_pass': observed['all_checks'], 'passed': observed['all_checks'] == expected})
    def changed(name, key, value, expected=False):
        docs = copy.deepcopy(fixture);docs[key] = value;trial(name, docs, expected)
    trial('valid_default_local_library', fixture, True)
    changed('valid_xsim_lib_mapping', 'xsim.ini', 'cfo_xpm=xsim_lib/cfo_xpm\n', True)
    changed('valid_windows_path_case', 'xvlog.log', analysis.replace('d:\\', 'D:\\').replace('d:/008_ma_dev/t11_cfo', 'D:/008_MA_Dev/T11_CFO'), True)
    for name in REQUIRED:
        docs = copy.deepcopy(fixture);docs.pop(name);trial('missing_' + name, docs, False)
    changed('empty_optional_xelab_log', 'xelab.log', '')
    changed('echo_without_actual_compile', 'compile.bat', 'echo "xvlog -prj ' + PRJ + '"')
    changed('wrong_actual_project', 'compile.bat', fixture['compile.bat'].replace('call xvlog', 'call xvlog').replace('-prj ' + PRJ, '-prj other.prj'))
    changed('working_directory_changed', 'compile.bat', 'pushd C:/other\n' + fixture['compile.bat'])
    changed('hidden_compile_response_file', 'compile.bat', fixture['compile.bat'].replace('--incr', '-f hidden.txt --incr'))
    changed('duplicate_private_prj_source', PRJ, project + '\nsv cfo_xpm "' + paths[0] + '"\n')
    official = 'C:/NIFPGA/programs/Vivado2021_1/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv'
    changed('extra_official_prj_source', PRJ, project + '\nsv xpm "' + official + '"\n')
    changed('extra_vendor_vcomp_prj_source', PRJ, project + '\nvhdl xpm "C:/NIFPGA/programs/Vivado2021_1/data/ip/xpm/xpm_VCOMP.vhd"\n')
    changed('wrong_prj_library', PRJ, project.replace('sv cfo_xpm', 'sv xpm'))
    changed('wrong_compile_library', 'xvlog.log', analysis.replace('into library cfo_xpm', 'into library xpm', 1))
    changed('extra_official_analysis', 'compile.log', analysis + '\nINFO: [VRFC 10-2263] Analyzing SystemVerilog file "' + official + '" into library xpm')
    changed('duplicate_private_analysis', 'xvlog.log', analysis + '\n' + analysis.splitlines()[0])
    changed('xpm_precedes_private', 'elaborate.log', elaborate.replace('-L cfo_xpm -L uvm -L xpm', '-L xpm -L cfo_xpm'))
    changed('echo_command_is_not_actual_xelab', 'elaborate.log', elaborate.replace('Running:', 'echo'))
    changed('private_library_directory_override', 'elaborate.log', elaborate.replace('-L cfo_xpm', '-L cfo_xpm=C:/global'))
    changed('alternate_ini_bypasses_audit', 'elaborate.log', elaborate.replace('-L cfo_xpm', '-initfile C:/other.ini -L cfo_xpm'))
    changed('missing_expected_module', 'elaborate.log', elaborate.replace('Compiling module cfo_xpm.xpm_fifo_base(SYNTHETIC=1)', ''))
    changed('module_name_prefix_is_not_match', 'elaborate.log', elaborate.replace('cfo_xpm.xpm_fifo_base(', 'cfo_xpm.xpm_fifo_base_other('))
    changed('global_xpm_binding', 'elaborate.log', elaborate + '\nCompiling module xpm.xpm_fifo_reg_bit')
    changed('other_library_xpm_binding', 'elaborate.log', elaborate + '\nCompiling module xil_defaultlib.xpm_fifo_reg_bit')
    changed('missing_mapping', 'xsim.ini', 'xpm=C:/installed/xpm\n')
    changed('empty_mapping', 'xsim.ini', 'cfo_xpm=\n')
    changed('duplicate_mapping', 'xsim.ini', 'cfo_xpm=xsim.dir/cfo_xpm\ncfo_xpm=xsim.dir/cfo_xpm\n')
    changed('outside_mapping', 'xsim.ini', 'cfo_xpm=../../outside\n')
    changed('installed_mapping', 'xsim.ini', 'cfo_xpm=C:/NIFPGA/programs/Vivado2021_1/data/xsim/ip/xpm\n')
    changed('environment_mapping', 'xsim.ini', 'cfo_xpm=$RDI_DATADIR/xsim/ip/xpm\n')
    changed('root_only_mapping', 'xsim.ini', 'cfo_xpm=.\n')
    changed('drive_relative_mapping', 'xsim.ini', 'cfo_xpm=D:relative\n')
    changed('mapping_library_case_mismatch', 'xsim.ini', 'CFO_XPM=xsim.dir/cfo_xpm\n')
    good = all(row['passed'] for row in outcomes)
    return {'schema': 'link010r1_binding_self_check_v1', 'status': 'PASS' if good else 'FAIL', 'all_checks': good,
            'native_started': False, 'filesystem_fixtures_created': False, 'synthetic_in_memory_only': True,
            'passed': sum(row['passed'] for row in outcomes), 'total': len(outcomes), 'cases': outcomes}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--simdir', help='Exact CFO_LINK010R1 behavioral XSim directory')
    group.add_argument('--self-check', action='store_true', help='Synthetic in-memory parser counterexamples only')
    args = parser.parse_args(argv)
    result = self_check() if args.self_check else run(args.simdir)
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['all_checks'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
