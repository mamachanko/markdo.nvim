#!/usr/bin/env python3
"""Record the actual Neovim ext_linegrid UI as a small, lossless animated GIF."""
import argparse
import os
import selectors
import subprocess
import time
from pathlib import Path

import msgpack
from PIL import Image, ImageDraw, ImageFont

args = argparse.ArgumentParser(description=__doc__)
args.add_argument('--nvim', default='nvim')
args.add_argument('--font', default='/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf')
args = args.parse_args()
root = Path(__file__).resolve().parent.parent
os.chdir(root)
proc = subprocess.Popen([args.nvim, '--embed', '-u', 'NONE', '-n'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
selector = selectors.DefaultSelector()
selector.register(proc.stdout, selectors.EVENT_READ)
unpacker = msgpack.Unpacker(raw=False)
grid, attrs, replies, frames, durations = [], {}, {}, [], []
foreground, background, cursor, serial = 0xD0D0D0, 0x1C1C1C, (0, 0), 0


def redraw(events):
    global grid, foreground, background, cursor
    for event, *calls in events:
        for call in calls:
            if event == 'grid_resize':
                _, width, height = call
                grid = [[(' ', 0) for _ in range(width)] for _ in range(height)]
            elif event == 'grid_clear':
                grid = [[(' ', 0) for _ in row] for row in grid]
            elif event == 'default_colors_set':
                foreground, background = call[:2]
            elif event == 'hl_attr_define':
                attrs[call[0]] = call[1]
            elif event == 'grid_cursor_goto':
                cursor = (call[1], call[2])
            elif event == 'grid_line':
                _, row, col, cells, *_ = call
                highlight = 0
                for cell in cells:
                    text = cell[0]
                    if len(cell) > 1:
                        highlight = cell[1]
                    for _ in range(cell[2] if len(cell) > 2 else 1):
                        grid[row][col] = (text, highlight)
                        col += 1
            elif event == 'grid_scroll':
                _, top, bottom, left, right, rows, cols = call
                old = [row[:] for row in grid]
                for row in range(top, bottom):
                    for col in range(left, right):
                        r, c = row + rows, col + cols
                        grid[row][col] = old[r][c] if top <= r < bottom and left <= c < right else (' ', 0)


def pump(seconds=0.15):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if not selector.select(max(0, end - time.monotonic())):
            break
        chunk = os.read(proc.stdout.fileno(), 65536)
        if not chunk:
            raise RuntimeError('Neovim exited unexpectedly')
        unpacker.feed(chunk)
        for message in unpacker:
            if message[0] == 1:
                replies[message[1]] = message[2:]
            elif message[0] == 2 and message[1] == 'redraw':
                redraw(message[2])


def rpc(method, *params):
    global serial
    serial += 1
    proc.stdin.write(msgpack.packb([0, serial, method, list(params)]))
    proc.stdin.flush()
    deadline = time.monotonic() + 10
    while serial not in replies:
        if time.monotonic() > deadline:
            raise TimeoutError(method)
        pump(0.1)
    error, result = replies.pop(serial)
    if error:
        raise RuntimeError(error)
    return result


font = ImageFont.truetype(args.font, 22)
cell_width, cell_height, padding = 14, 29, 12


def capture(milliseconds):
    pump()
    im = Image.new('RGB', (len(grid[0]) * cell_width + padding * 2, len(grid) * cell_height + padding * 2), f'#{background:06x}')
    draw = ImageDraw.Draw(im)
    for row, line in enumerate(grid):
        for col, (text, highlight) in enumerate(line):
            style = attrs.get(highlight, {})
            fg, bg = style.get('foreground', foreground), style.get('background', background)
            if style.get('reverse'):
                fg, bg = bg, fg
            x, y = padding + col * cell_width, padding + row * cell_height
            draw.rectangle((x, y, x + cell_width - 1, y + cell_height - 1), fill=f'#{bg:06x}')
            draw.text((x, y + 1), text, font=font, fill=f'#{fg:06x}')
    row, col = cursor
    x, y = padding + col * cell_width, padding + row * cell_height
    draw.rectangle((x, y, x + cell_width - 1, y + cell_height - 1), outline='#ffcf66', width=2)
    frames.append(im)
    durations.append(milliseconds)


try:
    rpc('nvim_ui_attach', 40, 18, {'rgb': True, 'ext_linegrid': True})
    rpc('nvim_exec_lua', """
      vim.opt.rtp:prepend(vim.fn.getcwd())
      vim.opt.termguicolors = true
      vim.opt.swapfile = false
      vim.opt.laststatus = 2
      vim.opt.statusline = ' morning.md %= Mark Do '
      vim.opt.shortmess:append('I')
      vim.cmd.colorscheme('habamax')
      vim.cmd('syntax on')
      vim.cmd('edit examples/runbook.md')
      vim.bo.filetype = 'markdown'
      vim.cmd('runtime plugin/markdo.lua')
      vim.api.nvim_win_set_cursor(0, {4, 2})
    """, [])
    capture(1600)
    rpc('nvim_input', ':MarkDoRun')
    capture(1400)
    rpc('nvim_input', '\r')
    pump(0.1)
    capture(1000)
    pump(1.1)
    assert rpc('nvim_exec_lua', 'return vim.b.markdo_exit_code', []) == 0
    capture(2600)
    # The documented terminal normal-mode escape and q mapping.
    rpc('nvim_input', '\x1c\x0eq')
    pump(0.3)
    rpc('nvim_input', ':MarkDoDone')
    capture(1200)
    rpc('nvim_input', '\r')
    capture(1700)
    rpc('nvim_input', '6j:MarkDoDone')
    capture(1200)
    rpc('nvim_input', '\r')
    capture(2600)
    final = rpc('nvim_buf_get_lines', 0, 0, -1, False)
    assert final[2].startswith('- [x]') and final[3].startswith('  - [x]') and final[9].startswith('  - [x]'), final
    frames[0].save(root / 'docs/demo.gif', save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True)
    print(f'Recorded {len(frames)} actual Neovim UI frames ({sum(durations) / 1000:.1f}s) to docs/demo.gif')
finally:
    proc.terminate()
    proc.wait(timeout=5)
