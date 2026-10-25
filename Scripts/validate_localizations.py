#!/usr/bin/env python3
"""Validate the shipped catalogs, metadata, source keys and printf contracts."""
import collections
import json
from pathlib import Path
import re
import subprocess
import sys

ENTRY = re.compile(r'/\*.*?\*/|//[^\n]*|("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;', re.S)
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(hh|ll|[hljztL])?([@diuoxXfFeEgGaAcCsSp])|%%')


# Stable menu keys have explicit format contracts; legacy sentence keys encode
# their contract directly in the key.
NAMED_FORMATS = {key: {1: "@"} for key in ("menu.about", "menu.hide", "menu.quit")}

def load_catalog(path):
    text = path.read_text(encoding='utf-8')
    keys = [json.loads(match[1]) for match in ENTRY.finditer(text) if match[1]]
    duplicates = [key for key, count in collections.Counter(keys).items() if count > 1]
    if duplicates:
        raise ValueError(f'{path}: duplicate keys: {duplicates}')
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], capture_output=True, text=True, check=True)
    values = json.loads(result.stdout)
    if len(keys) != len(values):
        raise ValueError(f'{path}: entries must use quoted keys and values')
    if any(not isinstance(value, str) or not value.strip() for value in values.values()):
        raise ValueError(f'{path}: empty or non-string translation')
    return values


def signature(text):
    """Argument positions and ABI types, not wording or display order."""
    result = {}
    sequential = 0
    uses_positions = set()
    for match in FORMAT.finditer(text):
        if match[0] == '%%':
            continue
        uses_positions.add(bool(match[1]))
        sequential += 1
        position = int(match[1]) if match[1] else sequential
        kind = (match[2] or '') + match[3]
        if position < 1 or (position in result and result[position] != kind):
            raise ValueError('inconsistent printf argument position/type')
        result[position] = kind
    if len(uses_positions) > 1:
        raise ValueError('mixed positional and sequential printf arguments')
    return result


def validate(root):
    errors = []
    metadata = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(root / 'AppResources/Info.plist')]))
    languages = metadata['CFBundleLocalizations']
    paths = {path.parent.name.removesuffix('.lproj'): path for path in (root / 'AppResources').glob('*.lproj/Localizable.strings')}
    enum_source = (root / 'Sources/FastConvert/AppLanguage.swift').read_text()
    enum_languages = re.findall(r'^\s*case \w+ = "([a-zA-Z-]+)"', enum_source, re.M)
    if len(set(languages)) != len(languages) or set(languages) != set(paths) or set(languages) != set(enum_languages):
        errors.append('Language enum, CFBundleLocalizations and .lproj directories must match exactly')
    catalogs = {language: load_catalog(path) for language, path in paths.items()}
    reference = catalogs['en']
    for language, catalog in catalogs.items():
        for key in sorted(set(reference) - set(catalog)):
            errors.append(f'{language}: missing key {key!r}')
        for key in sorted(set(catalog) - set(reference)):
            errors.append(f'{language}: unexpected key {key!r}')
        for key, value in catalog.items():
            if key not in reference:
                continue
            try:
                expected = signature(reference[key])
                if NAMED_FORMATS.get(key, signature(key)) != expected or signature(value) != expected:
                    errors.append(f'{language}: printf argument mismatch for {key!r}')
                if expected and FORMAT.sub('', value).count('%'):
                    errors.append(f'{language}: unescaped percent in formatted translation {key!r}')
            except ValueError as error:
                errors.append(f'{language}: {key!r}: {error}')
    source_pattern = re.compile(r'(?:L10n\.(?:text|format)\(\s*|(?:reasonKey|solutionKey):\s*)"((?:\\.|[^"\\])*)"')
    for path in (root / 'Sources/FastConvert').glob('*.swift'):
        for match in source_pattern.finditer(path.read_text()):
            raw = match[1]
            if '\\(' in raw:
                errors.append(f'{path.name}: interpolated localization key {raw!r}')
                continue
            key = json.loads('"' + raw + '"')
            if key not in reference:
                errors.append(f'{path.name}: missing source key {key!r}')
    if errors:
        raise ValueError('\n'.join(errors))
    return len(languages), len(reference)


if __name__ == '__main__':
    try:
        languages, keys = validate(Path(__file__).resolve().parents[1])
        print(f'Localization validation passed: {languages} languages, {keys} keys each; printf contracts match.')
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Localization validation failed: {error}', file=sys.stderr)
        sys.exit(1)
