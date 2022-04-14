NIM=nim
PROG=release

all:$(PROG)

release:fasta2lmdb.nim
	$(NIM) c -d:release --mm:orc --define:useRealtimeGC --threads:on -d:nimEmulateOverflowChecks --bound_checks:off -p:./lib fasta2lmdb

dev:fasta2lmdb.nim
	$(NIM) c -u:release --opt:none --mm:orc --threads:on -d:nimEmulateOverflowChecks --bound_checks:off -p:./lib fasta2lmdb

clean:
	rm fasta2lmdb