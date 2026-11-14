# Recording the demo

[demo.gif](demo.gif) records the real Neovim 0.11.0 UI at **40 columns × 18 rows**
while executing the plugin against [examples/runbook.md](../examples/runbook.md).
The short loop shows the Run command, the terminal's greeting and exit code,
and two Done commands checking the children and rolling up the parent.

The recorder attaches to an embedded Neovim using its public UI protocol. It
renders Neovim's actual `ext_linegrid` redraw events, highlight colors, float
borders, and cursor into GIF frames; the buffer/output are not a mockup. Long
pauses are collapsed into frame durations. The narrow viewport and large
monospace font keep the demo readable when GitHub scales it to a phone.

To reproduce from the repository root on Linux, with Neovim 0.11+ and Python 3:

```sh
python3 -m venv /tmp/markdo-demo-venv
/tmp/markdo-demo-venv/bin/pip install pillow msgpack
/tmp/markdo-demo-venv/bin/python scripts/record-demo.py --nvim /path/to/nvim
```

Use `--font /path/to/monospace.ttf` if DejaVu Sans Mono is unavailable (for
example on macOS). Demo dependencies are optional and unrelated to the plugin
or CI tests. The recorder uses `-u NONE`, disables swap files, and never saves
its checklist edits to disk.
