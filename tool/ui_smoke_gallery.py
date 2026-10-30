"""Index synthetic Flutter captures; no network, real data, or image libraries."""
from html import escape
from pathlib import Path
import sys


def main(folder: Path) -> None:
    images = sorted(folder.glob("*.png"))
    if not images:
        raise SystemExit("No synthetic UI captures were produced")
    rows = "".join(
        f'<figure><figcaption>{escape(p.stem)}</figcaption>'
        f'<a href="{escape(p.name, quote=True)}"><img loading="lazy" '
        f'src="{escape(p.name, quote=True)}" alt="{escape(p.stem, quote=True)}"></a></figure>'
        for p in images
    )
    (folder / "index.html").write_text(
        '<!doctype html><meta charset="utf-8"><title>WHOOP synthetic UI checks</title>'
        '<style>body{font:16px system-ui;background:#c9ae84;color:#2a211b;margin:24px}'
        'main{display:flex;gap:24px;flex-wrap:wrap;align-items:start}'
        'figure{margin:0;width:330px}img{width:100%;height:auto}figcaption{padding:12px 0}</style>'
        f'<h1>WHOOP synthetic UI checks</h1><p>{len(images)} captures, including scroll positions. '
        'These use synthetic fixtures and a font substitute. They assert layout and selected '
        'interactions; they do not prove iPhone typography, gestures or OS delivery. '
        'Pixel-baseline skips remain separate.</p><main>' + rows + '</main>', encoding="utf-8"
    )
    print(f"Indexed {len(images)} synthetic captures")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
