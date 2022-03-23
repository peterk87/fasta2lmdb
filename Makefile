NIM=nim
PROG=fasta2lmdb

all:$(PROG)

fasta2lmdb:fasta2lmdb.nim ./lib/klib.nim
	$(NIM) c -d:release --mm:orc --threads:on -d:nimEmulateOverflowChecks --bound_checks:off -p:./lib -o:$@ $<
