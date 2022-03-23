# fasta2lmdb

Quickly save FASTA sequences to an LMDB key-value database for rapid retrieval.

## Rationale

[GISAID] provides an [LZMA] compressed FASTA of SARS-CoV-2 sequences download (e.g. `sequences_fasta_2022_03_23.tar.xz`), which although is very small compared to the uncompressed size of the FASTA (3GB for `tar.xz` vs over 250GB for uncompressed FASTA), this `tar.xz` file can be very slow to retrieve sequences of interest especially if different subsets of the GISAID sequences need to be retrieved.

To address this sequence retrieval bottleneck, `fasta2lmdb` was developed in the [Nim] language to generate an [LMDB] key-value database from a FASTA file using [klib.nim](https://github.com/lh3/biofast/blob/master/lib/klib.nim) from [lh3/biofast](https://github.com/lh3/biofast) for ultrafast FASTA parsing. Keys are FASTA sequence record names and values are the [Zstd] compressed nucleotide sequences.


## Install

```bash
git clone https://github.com/peterk87/fasta2lmdb.git
cd fasta2lmdb
make
./fasta2lmdb --help
```

## Usage

Sequences must be piped into `fasta2lmdb` as stdin, e.g.

```bash
$ xzcat sequences.fasta.xz | ./fasta2lmdb --dbpath /path/to/seqs_lmdb
```

### Recommended Usage with GISAID sequences_fasta_YYYY_mm_dd.tar.xz

Given a `sequences_fasta_YYYY_mm_dd.tar.xz` file from GISAID containing SARS-CoV-2 sequences, decompress the `tar.xz` file with [pixz] for rapid multithreaded decompression, piping stdout into `tar` to extract `sequences.fasta` and, optionally, piping into [pv] to watch progress/bandwidth, and finally piping into `fasta2lmdb` to write the sequences to an [LMDB] at `./gisaidlmdb`:

```bash
$ pixz -d < /path/to/sequences_fasta_2022_03_17.tar.xz | tar -xOf - sequences.fasta | pv -cN pixztar | ./fasta2lmdb --dbpath ./gisaidlmdb
```

The following messages should appear in the terminal with progress tracked by `pv`:
```
Creating DB at './gisaidlmdb'. Removing 'lock.mdb' and 'data.mdb' if present.
map size set = 10995116277760
  pixztar: 4.10GiB 0:00:26 [ 157MiB/s] 
```

## Performance

Throughput for extracting `sequences_fasta_2022_03_23.tar.xz` and piping to `/dev/null` was around 450MiB/s:

```bash
$ pixz -d < /path/to/sequences_fasta_2022_03_17.tar.xz | tar -xOf - sequences.fasta | pv -cN pixztar > /dev/null
  pixztar: 2.58GiB 0:00:06 [ 458MiB/s] [         <=>    ]
```

`fasta2lmdb` can parse and save compressed sequences to an LMDB DB at around 1/3 (150-160MiB/s) the throughput of writing to `/dev/null`!

FASTA parsing with Python with [BioPython]'s [SimpleFastaParser]() and *not* compressing or saving sequences to an LMDB was clocked at around 60-65MiB/s.

```python
#!/usr/bin/env python
import sys

from Bio.SeqIO.FastaIO import SimpleFastaParser

def main():
    count = 0
    header_count = 0
    seq_count = 0
    try:
        for name, seq in SimpleFastaParser(sys.stdin):
            header = name.replace('hCoV-19/', '').replace(' ', '_').split('|', maxsplit=1)[0]
            count += 1
            header_count += len(header)
            seq_count += len(seq)
    finally:
        print(count, header_count, seq_count)
        print('DONE!')


if __name__ == '__main__':
    main()
```

Using [klib kseq.h](https://github.com/attractivechaos/klib/blob/master/kseq.h) with Python could result in better performance, but efficient multithreaded writes to the LMDB would still be an issue with Python unless maybe using Cython.


[Nim]: https://nim-lang.org/
[LZMA]: https://tukaani.org/xz/
[pixz]: https://github.com/vasi/pixz
[pv]: http://www.ivarch.com/programs/pv.shtml
[LMDB]: http://www.lmdb.tech/doc/
[GISAID]: https://www.gisaid.org/
[Zstd]: https://github.com/facebook/zstd