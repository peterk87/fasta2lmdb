# fasta2lmdb

Quickly save FASTA sequences to an LMDB key-value database for extremely rapid retrieval (get 100k SARS-CoV-2 sequences from a `fasta2lmdb` DB in less than 5 seconds!). Compress sequences with [Zstd] for a DB less than twice as large as a `.tar.xz` (if you train a Zstd dictionary on your sequences)!

## Rationale

[GISAID] provides an [LZMA] compressed FASTA of SARS-CoV-2 sequences download (e.g. `sequences_fasta_2022_03_23.tar.xz`), which although is very small compared to the uncompressed size of the FASTA (3GB for `tar.xz` vs over 250GB for uncompressed FASTA), this `tar.xz` file can be very slow to retrieve sequences of interest especially if different subsets of the GISAID sequences need to be retrieved.

To address this sequence retrieval bottleneck, `fasta2lmdb` was developed in the [Nim] language to generate an [LMDB] key-value database from a FASTA file using [klib.nim](https://github.com/lh3/biofast/blob/master/lib/klib.nim) from [lh3/biofast](https://github.com/lh3/biofast) for ultrafast FASTA parsing. Keys are FASTA sequence record names and values are the [Zstd] compressed nucleotide sequences.

## Install

### Download Linux binary

Download the pre-compiled Linux binary under the [latest release](https://github.com/peterk87/fasta2lmdb/releases/) and put it somewhere on your `PATH`.

### Compile from source

If you have [Nim] and [Nimble] installed, clone the repo and use [Nimble] to get the [Nim] dependencies and compile `fasta2lmdb`:

```bash
git clone https://github.com/peterk87/fasta2lmdb.git
cd fasta2lmdb
nimble build --verbose
./fasta2lmdb -h
```

#### Compile statically linked binary from source

[LMDB] will need to be compiled from source to create a `liblmdb.a` file necessary for static linking.

Download, build and install the latest version of LMDB:

```bash
curl -SLk https://github.com/LMDB/lmdb/archive/refs/tags/LMDB_0.9.29.tar.gz | tar -xzf -
cd lmdb-LMDB_0.9.29/libraries/liblmdb/
make
sudo make install
[[ -f "/usr/local/lib/liblmdb.a" ]] || (echo "'/usr/local/lib/liblmdb.a' does not exist! Static compilation may not work." && false)
```

To compile a portable binary with static linking of dependencies with optional stripping of unnecessary symbols and [UPX](https://github.com/upx/upx) binary compression:

```bash
nimble build -d:static --verbose
# optional strip unnecessary symbols from binary and compress with UPX
strip -s ./fasta2lmdb
upx --best ./fasta2lmdb
```

**References**

- [Nim: Deploying static binaries](https://scripter.co/nim-deploying-static-binaries/)


## Usage

You can either create an LMDB DB from FASTA sequences piped into `fasta2lmdb` or you can retrieve FASTA sequences from an LMDB with sequence IDs from a text file (one sequence ID per line).


Sequences must be piped into `fasta2lmdb` as stdin, e.g.

```bash
$ xzcat sequences.fasta.xz | ./fasta2lmdb --dbpath /path/to/seqs_lmdb
```

GISAID SARS-CoV-2 `sequences_fasta_YYYY_mm_dd.tar.xz` into an LMDB DB

```bash
$ pixz -d < /path/to/sequences_fasta_2022_03_17.tar.xz | tar -xOf - sequences.fasta | pv -cN pixztar | ./fasta2lmdb --dbpath ./gisaidlmdb
```

Retrieve sequences from LMDB

```bash
$ ./fasta2lmdb --dbpath /path/to/gisaidlmdb --seqids seqids.txt > seqs.fasta
```

- **NOTE:** if the sequences are compressed with a Zstd dictionary, the dictionary will be retrieved from the LMDB `info` DB and used to decompress the sequences. Compression with a Zstd dictionary is *highly* recommended since it cuts the LMDB size drastically (e.g. around 100 GB without a Zstd dictionary to only 4-5 GB with a dictionary for the GISAID SARS-CoV-2 sequences from 2022-03-17 *or* from around 9000 bytes Zstd compressed without a dictionary to only 300-500 bytes with a dictionary per SARS-CoV-2 sequence).

### Recommended Usage with GISAID sequences_fasta_YYYY_mm_dd.tar.xz

It is highly recommended that you train a Zstd dictionary on your input sequences before creating an LMDB with `fasta2lmdb`. You can use the `train_zstd_dictionary_fasta_seqs.py` script to train a dictionary: 

```bash
$ pixz -d < /path/to/gisaid/sequences_fasta_2022_03_17.tar.xz | tar -xOf - sequences.fasta | python train_zstd_dictionary_fasta_seqs.py --n-seqs 1000
```

You should see the following terminal output and a `zstd_dictionary` file should be created:

```
[2022-04-14 15:15:26] INFO     Reading 1000 FASTA sequences from stdin and saving 
                               to "/tmp/train_zstd_dictionary_fasta_seqs.pyrfwkcaxq"
                               for Zstd dictionary training.
[2022-04-14 15:15:27] INFO     Running Zstd training with command: $ ['zstd', '--train', '--maxdict', '112640', '-o', 
                               'zstd_dictionary', '-r', '/tmp/train_zstd_dictionary_fasta_seqs.pyrfwkcaxq']
Trying 5 different sets of parameters
k=1998
d=8
f=20
steps=4
split=75
accel=1
Save dictionary of size 112640 into file /path/to/zstd_dictionary
                      INFO     Done! Zstd dictionary at "zstd_dictionary"
```


Given a `sequences_fasta_YYYY_mm_dd.tar.xz` file from GISAID containing SARS-CoV-2 sequences, decompress the `tar.xz` file with [pixz] for rapid multithreaded decompression, piping stdout into `tar` to extract `sequences.fasta` and, optionally, piping into [pv] to watch progress/bandwidth, and finally piping into `fasta2lmdb` to write the sequences to an [LMDB] at `./gisaidlmdb`:

```bash
$ pixz -d < /path/to/sequences_fasta_2022_02_10.tar.xz | tar -xOf - sequences.fasta | pv -cN pixztar | ./fasta2lmdb --dbpath ./gisaidlmdb --zstddict zstd_dictionary
```

The following messages should appear in the terminal with progress tracked by `pv`:
```
[15:02:53] - INFO: Creating DB at '/path/to/gisaidlmdb'. Removing 'lock.mdb' and 'data.mdb' if present.
[15:02:54] - INFO: map size set = 10737418240
[15:02:54] - INFO: Initialized DBs
[15:02:54] - INFO: No dict read from DB. zstdDict=zstd_dictionary
[15:02:54] - INFO: Saved zstd dictionary from 'zstd_dictionary' to LMDB
[15:02:54] - INFO: Reading records from stdin and saving to LMDB '/path/to/gisaidlmdb'
     seqs:  223GiB 0:05:55 [ 644MiB/s] [                                                                  <=>          ]
[15:08:49] - INFO: Read 8050840 records!
[15:08:49] - INFO: DONE!
```

Add new sequences to an existing LMDB with

```bash
$ pixz -d < /path/to/sequences_fasta_2022_04_14.tar.xz | tar -xOf - sequences.fasta | pv -cN pixztar | ./fasta2lmdb --dbpath ./gisaidlmdb
```

- **NOTE:** Only new sequences with sequence IDs that do not exist in the DB will be added so this should be faster than creating a new DB. 

### ZStandard Dictionary for better compression!

It's highly recommended that a [ZStandard dictionary](https://facebook.github.io/zstd/) be generated from a sampling of the sequences you wish to put into the LMDB for greater compression.

For all SARS-CoV-2 sequences downloaded on 2022-03-17 from GISAID (as a `tar.xz` file 3.1 GB in size), the uncompressed size was 261GB compared to 26 GB compressed in an LMDB without a dictionary versus 5.4 GB in an LMDB with a dictionary built from a sampling of 10,000 sequences.

- **LMDB of Zstd dictionary compressed sequences was only around 1.7X bigger than the sequences compressed with XZ!**

#### LMDB with ZStandard Dictionary from GISAID SARS-CoV-2

```bash
$ pixz -d < sequences_fasta_2022_03_17.tar.xz \
  | tar -xOf - sequences.fasta \
  | pv -cN pixztar \
  | ./fasta2lmdb --dbpath /path/to/gisaid-lmdb --zstdDict gisaid-zstd-dictionary
```

```
[08:50:44] - INFO: Creating DB at '/path/to/gisaid-lmdb'. Removing 'lock.mdb' and 'data.mdb' if present.
[08:50:44] - INFO: map size set = 10995116277760
[08:50:44] - INFO: Initialized DBs
[08:50:44] - INFO: Saved zstd dictionary from 'gisaid-zstd-dictionary' to LMDB
[08:50:44] - INFO: Reading records from stdin and saving to LMDB '/path/to/gisaid-lmdb'
  pixztar:  261GiB 0:06:37 [ 672MiB/s] [<=>       ]
[08:57:22] - INFO: DONE!
```

Very reasonable size for a DB - only 5.4 GB vs 3.1 for `sequences_fasta_2022_03_17.tar.xz`:

```
$ tree -h
[4.0K]  .
├── [5.4G]  data.mdb
└── [8.0K]  lock.mdb
```

- **NOTE:** Size of database may vary depending on how Zstd dictionary training goes, but the size of the LMDB should be a fraction of the size without a dictionary.

## Performance

> Benchmarking and performance testing was done on laptop with dual M.2 SSD drives in RAID-0. Performance might be better or worse depending on your setup.

Throughput for extracting `sequences_fasta_2022_03_23.tar.xz` and piping to `/dev/null` was around 2.2GiB/s:

```bash
$ pixz -d < /path/to/sequences_fasta_2022_03_17.tar.xz | tar -xOf - sequences.fasta | pv -cN pixztar > /dev/null
  pixztar: 41.1GiB 0:00:19 [2.18GiB/s]
```

`fasta2lmdb` can parse and save compressed sequences to an LMDB DB at around 1/3 (680-730MiB/s) the throughput of writing to `/dev/null`!

FASTA parsing with Python with [BioPython]'s [SimpleFastaParser]() and *not* compressing or saving sequences to an LMDB was clocked at around 350-400MiB/s.

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

## Retrieving sequences from the LMDB DB with Python

Requires:

- [lmdb]
- [zstandard]

Install dependencies with `pip`

```bash
pip install zstandard lmdb

```

Example Python script to 

```python
#!/usr/bin/env python
from typing import Dict, List
import zstandard
import lmdb
from time import time
import random


# Open read-only connection to LMDB DB
env = lmdb.open('/path/to/lmdb_dir', readonly=True)

# Check number of entries
with env.begin() as txn:
    length = txn.stat()['entries']
    print('DB entries:', length)
#=> DB entries: 9388892

# Get all keys from DB (not recommended; in reality, you'd be interested in a 
# specific set of sequences, e.g. sequences based on queries of the GISAID 
# metadata table (e.g. get all Canadian sequences))
# NOTE: keys fetched from DB will be bytes (b'Canada/strain123/2022') 
#       rather than string ('Canada/strain123/2022'). String keys need to be
#       encoded to bytes (e.g. 'abc'.encode() => b'abc')
t0 = time()
db_keys: List[bytes] = []
with env.begin() as txn:
    with txn.cursor() as curs:
        for k in curs.iternext(keys=True, values=False):
            db_keys.append(k)
print('fetched', len(db_keys), 'keys in', time() - t0, 'sec')
#=> fetched 9388892 keys in 83.55254173278809 sec

# Try getting 1,000 sequences from the DB
# Get random indexesparallel(delayed(txn.get)(seqid) for seqid in seqids)
idxs: List[int] = list(range(len(db_keys)))
random.shuffle(idxs)
N = 1000
idxs = idxs[:N]

# Put sequences into dict (in reality you'd probably be writing 
# straight to a file instead or processing them one at a time)
# NOTE: It might be faster to parallelize the following with multiprocessing or
#       multithreading since LMDB reads scale linearly with CPU threads, but
#       CPython threading is notoriously slow and forking processes can be 
#       expensive.
t0 = time()
header_seq: Dict[str, str] = {}
with env.begin() as txn:
    for idx in idxs:
        seqid = db_keys[idx]
        # if key is string, need to encode to bytes
        #  seqid = seqid.encode()
        # NOTE: values fetched from DB will be bytes so it may be necessary to 
        # decode to string to use without issues
        header_seq[seqid.decode()] = zstandard.decompress(txn.get(seqid)).decode()
print('time taken (sec):', time() - t0)
#=> time taken (sec): 1.5
print(len(header_seq))
#=> 1000
print('sum of seq lens:', sum(len(v) for v in header_seq.values()))
#=> sum of seq lens: 133742069
print(seqid)
#=> <trimmed GISAID virus name>
print(header_seq[seqid])
#=> ATCG....
```

## Known issues

- memory usage increases as more key-value pairs are added to the LMDB. Currently, LMDB Env is closed and reopened to try to limit memory usage by freeing up. An equivalent Rust solution has the same issues. Maybe the LMDB code is aggressively caching keys and/or values? 

## Changelog

### 0.2.1 [2022-04-20]

Fixed static compilation of `fasta2lmdb` for a more portable binary.

### 0.2.0 [2022-04-14]

Added

- Optional but highly recommended Zstd compression with a Zstd trained dictionary on sample input for better compression and faster compression/decompression.
- `info` DB added to output LMDB containing Zstd dictionary if provided and other metadata about LMDB creation.
- Add new sequences to an existing LMDB and use Zstd dictionary in LMDB if present (`$ pixz new_seqs | ./fasta2lmdb --dbpath /path/to/existing_lmdb`)
- `train_zstd_dictionary_fasta_seqs.py` to help train Zstd dictionary for better compression of sequences for `fasta2lmdb`
- output sequences from `fasta2lmdb` generated LMDB with a file containing sequence IDs using `fasta2lmdb` (`$ ./fasta2lmdb --dbpath /path/to/seqslmdb --seqids seqids.txt > seqs.fasta`)


### 0.1.0 [2022-03-22]

Initial alpha release.


[lmdb]: https://github.com/jnwatson/py-lmdb/
[zstandard]: https://github.com/indygreg/python-zstandard
[BioPython]: https://biopython.org/
[Nim]: https://nim-lang.org/
[Nimble]: https://github.com/nim-lang/nimble
[LZMA]: https://tukaani.org/xz/
[pixz]: https://github.com/vasi/pixz
[pv]: http://www.ivarch.com/programs/pv.shtml
[LMDB]: http://www.lmdb.tech/doc/
[GISAID]: https://www.gisaid.org/
[Zstd]: https://github.com/facebook/zstd