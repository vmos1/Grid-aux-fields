#!/usr/bin/env python3
"""Remove preprocessor blocks conditioned on one macro, like `unifdef -U<MACRO>`.

Handles, at any nesting depth:
    #ifdef MACRO / #ifndef MACRO
    #if defined(MACRO) / #if !defined(MACRO) / #if defined MACRO / #if ! defined MACRO
with their #else and #endif. For a block whose condition is the macro alone, the
false branch is kept and the directives are dropped. Conditionals on anything else
are left untouched (their nesting is tracked so the right #endif is matched).
A conditional that mixes the macro with other terms (e.g. `#if defined(MACRO) && X`)
or uses #elif inside a macro block is reported and left alone.

Usage: strip_ifdef.py MACRO file [file ...]      (edits in place, prints a summary)
"""
import re
import sys

def strip(text, macro):
    only_true = re.compile(r'^\s*#\s*(ifdef\s+' + macro + r'|if\s+defined\s*\(\s*' + macro + r'\s*\)|if\s+defined\s+' + macro + r')\s*(//.*|/\*.*)?$')
    only_false = re.compile(r'^\s*#\s*(ifndef\s+' + macro + r'|if\s+!\s*defined\s*\(\s*' + macro + r'\s*\)|if\s+!\s*defined\s+' + macro + r')\s*(//.*|/\*.*)?$')
    any_if = re.compile(r'^\s*#\s*(if|ifdef|ifndef)\b')
    any_elif = re.compile(r'^\s*#\s*elif\b')
    any_else = re.compile(r'^\s*#\s*else\b')
    any_endif = re.compile(r'^\s*#\s*endif\b')
    mentions = re.compile(r'\b' + macro + r'\b')

    out = []
    # stack entries: (kind, keeping_before) where kind is 'other', 'macro_true', 'macro_false'
    stack = []
    keep = True
    removed = 0
    warnings = []
    for lineno, line in enumerate(text.splitlines(keepends=True), 1):
        if any_if.match(line):
            if only_true.match(line):
                stack.append(('macro_true', keep, 'true'))   # inside the true branch: drop
                keep = False
                removed += 1
                continue
            if only_false.match(line):
                stack.append(('macro_false', keep, 'false'))  # inside the false branch of ifndef: keep
                removed += 1
                continue
            if mentions.search(line):
                warnings.append('line %d: mixed condition left alone: %s' % (lineno, line.strip()))
            stack.append(('other', keep, None))
            if keep:
                out.append(line)
            continue
        if any_elif.match(line):
            if stack and stack[-1][0] != 'other':
                warnings.append('line %d: #elif inside a %s block, left alone' % (lineno, macro))
            if keep:
                out.append(line)
            continue
        if any_else.match(line):
            if stack and stack[-1][0] == 'macro_true':
                keep = stack[-1][1]          # entering the #else of #ifdef MACRO: keep if parent kept
                stack[-1] = ('macro_true', stack[-1][1], 'else')
                continue
            if stack and stack[-1][0] == 'macro_false':
                keep = False                 # entering the #else of #ifndef MACRO: drop
                stack[-1] = ('macro_false', stack[-1][1], 'else')
                continue
            if stack and stack[-1][0] == 'other' and stack[-1][1]:
                out.append(line)
            continue
        if any_endif.match(line):
            if not stack:
                warnings.append('line %d: unmatched #endif' % lineno)
                out.append(line)
                continue
            kind, keep_before, _ = stack.pop()
            if kind == 'other':
                if keep_before:
                    out.append(line)
                keep = keep_before
            else:
                keep = keep_before
            continue
        if keep:
            out.append(line)
    if stack:
        warnings.append('unbalanced conditionals at end of file (%d open)' % len(stack))
    return ''.join(out), removed, warnings

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    macro = sys.argv[1]
    for path in sys.argv[2:]:
        with open(path, encoding='utf-8', errors='surrogateescape') as f:
            text = f.read()
        new, removed, warnings = strip(text, macro)
        if removed or warnings:
            if new != text:
                with open(path, 'w', encoding='utf-8', errors='surrogateescape') as f:
                    f.write(new)
            print('%s: %d %s block(s) removed, %d -> %d lines' % (path, removed, macro, text.count('\n'), new.count('\n')))
            for w in warnings:
                print('  WARNING ' + w)

if __name__ == '__main__':
    main()
