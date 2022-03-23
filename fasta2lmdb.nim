import std/[os, threadpool, strformat]
import strutils
import terminal

import bytesequtils
import cligen
import zstd/compress
import lmdb
# import from lib/klib.nim; must compile with -p:./lib
import klib

proc flush_database_dir(dbname: string) =
  createDir dbname
  discard tryRemoveFile dbname & "/lock.mdb"
  discard tryRemoveFile dbname & "/data.mdb"

proc saveSeq(dbenv: LMDBEnv, name: string, comment: string, sequence: string) = 
  var header = name & " " & comment
  header = header.split('|', maxsplit=1)[0]
  header = header.replace(' ', '_')
  header = header.replace("hCoV-19/", "")
  var compressedSeq = compress(sequence, level=1)
  let txn = dbenv.newTxn()
  let dbi = txn.dbiOpen("", 0)
  var s = toStrBuf(compressedSeq)
  try:
    txn.put(dbi, header, s)
    txn.commit()
  except Exception as ex:
    echo fmt"WTF! header={header} seqlen={len(sequence)}"
    echo "Error: ", ex.msg, "(", ex.name, ")"
    txn.abort()
    raise ex
  finally:
    dbenv.close(dbi)

proc fasta2lmdb(dbpath="./gisaidseqs", mapSize: uint=10485760 * 1024 * 1024, createDB=true) =
  ## Read FASTA records from stdin into LMDB key-value database
  ##
  ## Expected usage:
  ##
  ## $ pixz -d < sequences_fasta_YYYY_mm_dd.tar.xz | tar -xOf - sequences.fasta | fasta2lmdb --dbpath ./gisaidseqs
  ##
  if not isatty(stdin):
    if createDB:
      echo "Creating DB at '", dbpath, "'. Removing 'lock.mdb' and 'data.mdb' if present."
      flush_database_dir(dbpath)
    let dbenv = newLMDBEnv(dbpath, openflags=MAPASYNC or NOSYNC)
    discard envSetMapsize(dbenv, mapSize)
    echo "map size set = ", mapSize
    var f = xopen[GzFile]("-")
    defer: f.close()
    var rec: FastxRecord
    while f.readFastx(rec):
      spawn saveSeq(dbenv, rec.name, rec.comment, rec.seq)
    threadpool.sync()
    dbenv.envClose()
    echo "DONE!"
  else:
    raise newException(Exception, "No stdin stream present :-(")

dispatch(fasta2lmdb)