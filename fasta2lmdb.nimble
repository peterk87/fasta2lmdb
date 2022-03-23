# Package

version       = "0.1.0"
author        = "Peter Kruczkiewicz"
description   = "Quickly save FASTA sequences to an LMDB key-value database for rapid retrieval."
license       = "Apache-2.0"
bin           = @["fasta2lmdb"]


# Dependencies

requires "nim >= 1.6.4"
requires "bytesequtils >= 1.2.0"
requires "cligen >= 1.5.23"
requires "lmdb >= 0.1.2"
requires "zstd >= 0.5.0"
