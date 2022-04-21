#!/usr/bin/env python
import logging
import subprocess as sp
import sys
import tempfile
from pathlib import Path
from typing import Tuple, Iterator, List

import typer
from rich.console import Console
from rich.logging import RichHandler


def init_logging(verbose: bool) -> None:
    from rich.traceback import install
    console = Console(stderr=True, width=200)
    install(show_locals=True, word_wrap=True, console=console)
    logging.basicConfig(
        format="%(message)s",
        datefmt="[%Y-%m-%d %X]",
        level=logging.DEBUG if verbose else logging.INFO,
        handlers=[RichHandler(rich_tracebacks=True,
                              tracebacks_show_locals=True,
                              locals_max_string=None,
                              console=console)],
    )


def read_fasta(handle) -> Iterator[Tuple[str, str]]:
    # Skip any text before the first record (e.g. blank lines, comments)
    title = ""
    for line in handle:
        if line.startswith(">"):
            title = line[1:].rstrip()
            break
        else:
            # no break encountered - probably an empty file
            return
    lines: List[str] = []
    for line in handle:
        if line.startswith(">"):
            yield title, "".join(lines).replace(" ", "").replace("\r", "")
            lines = []
            title = line[1:].rstrip()
            continue
        lines.append(line.rstrip())
    yield title, "".join(lines).replace(" ", "").replace("\r", "")


def main(
        zstddict: Path = typer.Option(Path('zstd_dictionary'), '-o', '--zstddict', help='Zstd dictionary output path.'),
        n_seqs: int = typer.Option(1000, '-n', '--n-seqs', help='Number of sequences to train Zstd dictionary with.'),
        maxdict: int = typer.Option(112640, help='Limit Zstd dictionary to specified size'),
        verbose: bool = typer.Option(False, is_flag=True),
) -> None:
    """Train Zstd dictionary from FASTA sequences

    Example Usage:

    $ zcat sequences.fasta.gz | ./train_zstd_dictionary_fasta_seqs.py -d zstd_dictionary

    Only the sequences themselves will be used for training the Zstd dictionary.
    """
    init_logging(verbose)
    logging.debug(f'{zstddict=}|{n_seqs=}|{maxdict=}')
    if sys.stdin.isatty():
        logging.error(f'FASTA sequences need to be piped into this script via stdin. Example usage: '
                      f'"$ xzcat sequences.fasta.xz | {Path(__file__).name}"')
        sys.exit(1)

    with tempfile.TemporaryDirectory(prefix=Path(__file__).name) as tmpdir:
        tmpdir_path = Path(tmpdir)
        logging.info(f'Reading {n_seqs} FASTA sequences from stdin and saving to '
                     f'"{tmpdir}" for Zstd dictionary training.')
        for i, (_, seq) in enumerate(read_fasta(sys.stdin)):
            if i >= n_seqs:
                break
            seqfile = tmpdir_path / f'{i}'
            seqfile.write_text(seq)
        cmd = [
            'zstd', '--train',
            '--maxdict', f'{maxdict}',
            '-o', str(zstddict.resolve().absolute()),
            '-r', str(tmpdir_path.resolve().absolute())
        ]
        logging.info(f'Running Zstd training with command: $ {cmd}')
        sp.check_call(cmd)
    logging.info(f'Done! Zstd dictionary at "{zstddict.absolute()}"')


if __name__ == '__main__':
    typer.run(main)
