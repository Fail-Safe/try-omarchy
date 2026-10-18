#!/usr/bin/env python3
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
patch = (root / 'macos/patches/qemu-cocoa-clean-fullscreen.patch').read_text()
block = patch.split('diff --git a/ui/cocoa-clean-viewport.h b/ui/cocoa-clean-viewport.h\n')[1]
header = '\n'.join(line[1:] for line in block.splitlines()
                   if line.startswith('+') and not line.startswith('+++')) + '\n'
with tempfile.TemporaryDirectory(prefix='omarchy-clean-viewport-') as tmp:
    directory = pathlib.Path(tmp)
    (directory / 'cocoa-clean-viewport.h').write_text(header)
    (directory / 'test.c').write_text('''
#include <assert.h>
#include "cocoa-clean-viewport.h"
int main(void) {
    assert(cocoa_clean_viewport_height(2582, true, true) == 2576);
    assert(cocoa_clean_viewport_height(2576, true, true) == 2576);
    assert(cocoa_clean_viewport_height(2582, false, true) == 2582);
    assert(cocoa_clean_viewport_height(2582, true, false) == 2582);
    assert(cocoa_clean_viewport_height(600, true, true) == 600);
    for (unsigned h = 608; h <= 8192; h++) {
        unsigned v = cocoa_clean_viewport_height(h, true, true);
        assert(v <= h && h - v < 16);
        assert(v % 16 == 0);
        assert((v * 3) % 4 == 0);
        assert((v * 5) % 8 == 0);
    }
    return 0;
}
''')
    subprocess.run([shutil.which('cc'), '-Wall', '-Wextra', '-Werror',
                    str(directory / 'test.c'), '-o', str(directory / 'test')], check=True)
    subprocess.run([str(directory / 'test')], check=True)
print('Clean fullscreen geometry: exact target, disabled/windowed cases, firmware minimum and 7585 heights PASS')
