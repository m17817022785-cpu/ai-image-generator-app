from pathlib import Path
import os
import subprocess

path = Path('lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')

old = """              OutlinedButton.icon(
                onPressed: () => _setStudioHeaderCollapsed(false),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                label: const Text('展开创作面板'),
              ),
"""

if old in text:
    text = text.replace(old, '', 1)
    path.write_text(text, encoding='utf-8')
    print('Removed duplicate empty-state studio expand button.')
else:
    print('Duplicate empty-state studio expand button block not found; no source patch needed.')

if os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('GITHUB_EVENT_NAME') == 'push':
    status = subprocess.run(['git', 'diff', '--quiet', '--', str(path)], check=False)
    if status.returncode != 0:
        subprocess.run(['git', 'config', 'user.name', 'github-actions[bot]'], check=True)
        subprocess.run(['git', 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com'], check=True)
        subprocess.run(['git', 'add', str(path)], check=True)
        subprocess.run(['git', 'commit', '-m', 'ui: remove duplicate studio expand button'], check=True)
        subprocess.run(['git', 'push'], check=True)
        print('Committed and pushed home_screen duplicate button fix.')
    else:
        print('No home_screen source changes to commit.')
