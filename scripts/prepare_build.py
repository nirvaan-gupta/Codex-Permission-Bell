"""Generate matching local credentials without modifying tracked source files."""
import re
import secrets
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def prepare(stage: Path) -> None:
    local = ROOT / '.local'
    local.mkdir(exist_ok=True)
    token_path = local / 'bridge-token'
    if token_path.exists():
        token = token_path.read_text().strip()
        if not re.fullmatch(r'[0-9a-f]{64}', token):
            raise ValueError('Invalid local bridge token; expected 64 hexadecimal characters')
    else:
        token = secrets.token_hex(32)
        token_path.touch(mode=0o600, exist_ok=False)
        token_path.write_text(token + '\n')
    token_path.chmod(0o600)
    stage.mkdir(parents=True, exist_ok=True)
    source = (ROOT / 'Sources/main.swift').read_text()
    if '__BRIDGE_TOKEN__' not in source:
        raise ValueError('Expected token placeholder in Swift source')
    (stage / 'main.swift').write_text(source.replace('__BRIDGE_TOKEN__', token))
    extension = ROOT / 'dist/browser-extension'
    extension.mkdir(parents=True, exist_ok=True)
    for source_path in (ROOT / 'browser-extension').iterdir():
        if source_path.is_file():
            shutil.copy2(source_path, extension / source_path.name)
    background = extension / 'background.js'
    text = background.read_text()
    if '__BRIDGE_TOKEN__' not in text:
        raise ValueError('Expected token placeholder in extension source')
    background.write_text(text.replace('__BRIDGE_TOKEN__', token))
    background.chmod(0o600)

if __name__ == '__main__':
    prepare(Path(sys.argv[1]))
