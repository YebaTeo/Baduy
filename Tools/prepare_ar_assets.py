"""Package AR models using Apple's USD tools; keep original USDC sources intact."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--assets', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
for name in ('lumbung', 'pintal', 'tenun'):
    with tempfile.TemporaryDirectory() as directory:
        stage = Path(directory) / (name + '.usda')
        source_file = next((p for p in [args.assets / (name + '.usdz'), args.assets / (name + '.usdc')] if p.exists()), None)
        if source_file is None:
            raise FileNotFoundError(name)
        # Some exports are USD crates renamed to .usdz. USDZ must be a ZIP package.
        extension = '.usdc' if source_file.read_bytes()[:8] == b'PXR-USDC' else source_file.suffix
        input_file = Path(directory) / ('source' + extension)
        input_file.write_bytes(source_file.read_bytes())
        subprocess.run(['usdcat', str(input_file), '-o', str(stage)], check=True)
        source = stage.read_text()
        # Exported Blender environment light references an absent EXR. ARKit
        # supplies the real room's lighting; geometry/materials remain intact.
        source, count = re.subn(r'    def DomeLight "env_light"\s*\{[^{}]*\}\n', '', source)
        if count > 1:
            raise RuntimeError(f'{name}: unexpected exported environment lights; inspect asset')
        stage.write_text(source)
        output = args.output / (name + '.usdz')
        subprocess.run(['usdzip', '--arkitAsset', str(stage), str(output)], check=True)
        subprocess.run(['usdchecker', '--arkit', str(output)], check=True)
