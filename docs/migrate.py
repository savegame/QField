#!python3

import argparse
import pathlib
import subprocess
import os
from distutils.dir_util import copy_tree
import gettext

languages = ['de', 'fr', 'bg']
contexts = ['case-studies', 'data-formats', 'fieldwork', 'getting-started', 'index', 'install', 'prepare', 'support', 'synchronise']

parser = argparse.ArgumentParser(description='Migrate')
parser.add_argument('source', metavar='source_dir', type=str,
                    help='sorce directory')

args = parser.parse_args()

print(f'Migrating from {pathlib.Path(args.source)}')

translators = {} 
for lang in languages:
    ltranslators = []
    for cont in contexts:
        ltranslators.append(gettext.translation(cont, localedir='old_docs_translation/i18n/', languages=[lang]))
    translators[lang] = ltranslators

def generate_translations(md_file):
    md_basename, _ = os.path.splitext(md_file)
    md_trans_file = md_basename + '.de.md'

    block = ''
    with open(md_file, 'r') as f:
        with open(md_trans_file, 'w') as tf:
            for line in f.readlines():
                if not line.strip(' -=\n') and block:
                    tr = block
                    for translator in translators['de']:
                        trc = translator.gettext(block)
                        if trc != block:
                            tr = trc
                    tf.write(tr + '\n' + line)
                    block = ''
                else:
                    if block:
                        block += ' ' + line.rstrip('\n')
                    else:
                        block = line.rstrip('\n')
        with open(md_trans_file, 'r') as x:
            for line in x.readlines():
                print(line)
            exit(-1)

for rst_file in list(pathlib.Path(args.source).glob('**/*.rst')):
    rst_file_relpath = os.path.join('docs', rst_file.relative_to(args.source))
    basename, _ = os.path.splitext(rst_file_relpath)
    print(basename)
    if basename.endswith('index') and basename != 'docs/en/index':
        continue
    basedir = pathlib.Path(basename).parent
    md_file_relpath = os.path.join('docs', pathlib.Path(os.path.join(basename + '.md')).relative_to('docs/en/'))

    pathlib.Path(os.path.join('docs', basedir.relative_to('docs/en'))).mkdir(parents=True, exist_ok=True)

    subprocess.run(['pandoc', '-s', '-o', md_file_relpath, rst_file])
    subprocess.run(['sed', '-i', 's/{width=.*}//g', md_file_relpath])
    subprocess.run(['sed', '-i', r's|\(\](\)\.*/image|\1../assets/image|g', md_file_relpath])
    subprocess.run(['sed', '-i', r's/!\[/!!\[/g', md_file_relpath])

    generate_translations(md_file_relpath)

copy_tree(os.path.join(args.source, 'en/images'), 'docs/assets/images')

