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
args.add_argument('--output', default='docs/demo.gif')
args.add_argument('--stills', help='Optional directory for inspecting individual recorded frames')
args = args.parse_args()
root = Path(__file__).resolve().parent.parent
os.chdir(root)
proc = subprocess.Popen([args.nvim, '--embed', '-u', 'NONE', '-n'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
selector = selectors.DefaultSelector()
selector.register(proc.stdout, selectors.EVENT_READ)
unpacker = msgpack.Unpacker(raw=False)
grid, attrs, replies, frames, durations = [], {}, {}, [], []
completed = False
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
    if args.stills:
        target = Path(args.stills)
        target.mkdir(parents=True, exist_ok=True)
        im.save(target / f'{len(frames):02d}.png')


def lua(code, *values):
    return rpc('nvim_exec_lua', code, list(values))


try:
    rpc('nvim_ui_attach', 40, 18, {'rgb': True, 'ext_linegrid': True})
    lua("markdo_demo = dofile('scripts/demo.lua'); markdo_demo.setup()")
    capture(1100)
    for step in lua('return markdo_demo.steps'):
        lua('markdo_demo.prepare(...)', step['id'])
        rpc('nvim_input', ':' + step['command'])
        capture(600)
        rpc('nvim_input', '\r')
        pump(0.15)
        if step.get('message'):
            capture(step['hold'])
            if rpc('nvim_get_mode')['blocking']:
                rpc('nvim_input', '\r')
                pump()
            lua('markdo_demo.check(...)', step['id'])
        else:
            # A health report or wrapped notification may request acknowledgement.
            if rpc('nvim_get_mode')['blocking']:
                rpc('nvim_input', '\r')
                pump()
            lua('markdo_demo.check(...)', step['id'])
            capture(step['hold'])
        if step['id'] == 'health':
            lua('markdo_demo.health_details()')
            capture(1900)
    # Execution is last: real terminal input, live output, retained exit status.
    rpc('nvim_input', 'Neovim\r')
    lua('markdo_demo.check_running_output()')
    capture(700)
    lua('markdo_demo.check_exit()')
    capture(2300)
    rpc('nvim_input', '\x1c\x0eq')
    pump()
    lua('markdo_demo.check_closed()')
    capture(1200)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(output, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True)
    completed = True
    print(f'Recorded {len(frames)} real Neovim frames ({sum(durations) / 1000:.1f}s) to {output}')
finally:
    if proc.poll() is None:
        try:
            lua('if markdo_demo then markdo_demo.finish() end')
            proc.stdin.write(msgpack.packb([2, 'nvim_command', ['qa!']]))
            proc.stdin.flush()
            proc.wait(timeout=5)
        except Exception as error:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=5)
            if completed:
                raise RuntimeError('Neovim cleanup or clipboard restoration failed') from error
