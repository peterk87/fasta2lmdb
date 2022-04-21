import std/[os, threadpool, strformat]
import strutils
import terminal
import logging

import bytesequtils
import cligen
import lmdb
import zstd/compress
import zstd/decompress
# import from lib/klib.nim; must compile with -p:./lib
import klib

let VERSION = "0.2.2"
let INFO_DB_NAME = "info"
let logger = newConsoleLogger(fmtStr="[$time] - $levelname: ", useStderr=true)


proc flush_database_dir(dbname: string) =
  createDir dbname
  discard tryRemoveFile dbname & "/lock.mdb"
  discard tryRemoveFile dbname & "/data.mdb"

proc compressSeq(
    sequence: string,
    dict: string,
    doCompress: bool = true,
    level: int = 3): string =
  var s: string
  if doCompress:
    var cctx = new_compress_context()
    var compressedSeq: seq[byte]
    if dict != "":
      compressedSeq = compress(cctx, sequence, dict=dict, level=level)
    else:
      compressedSeq = compress(cctx, sequence, level=level)
    discard free_context(cctx)
    s = toStrBuf(compressedSeq)
  else:
    s = sequence
  return s

proc getHeader(name: string, comment: string): string =
  var header: string = ""
  if comment != "":
    header = name & " " & comment
  else:
    header = name
  # special case for GISAID SARS-CoV-2 sequences
  if header.startswith("hCoV-19/"):
    header = header.replace("hCoV-19/", "")
    header = header.split('|', maxsplit=1)[0]
    header = header.replace(' ', '_')
  return header

proc putSeq(dbenv: LMDBEnv, header: string, s: string) =
  var txn = dbenv.newTxn()
  var dbi = txn.dbiOpen("", 0)
  try:
    txn.put(dbi, header, s)
    txn.commit()
  except Exception as ex:
    txn.abort()
    raise ex
  finally:
    dbenv.close(dbi)

proc saveSeq(
    dbenv: LMDBEnv,
    dict: string,
    name: string, 
    comment: string, 
    sequence: string,
    compressSeqs: bool = true, 
    level: int = 3) =
  var header = getHeader(name, comment)
  var compressedSeq = compressSeq(dict=dict, sequence=sequence, doCompress=compressSeqs, level=level)
  putSeq(dbenv, header, compressedSeq)

proc initInfoDB(dbenv: LMDBEnv, compressSeqs: bool = true) =
  let txn = dbenv.newTxn()
  let dbi = txn.dbiOpen(INFO_DB_NAME, flags=CREATE)
  txn.put(dbi, "fasta2lmdb_version", VERSION)
  txn.put(dbi, "is_compressed", fmt"{compressSeqs}")
  txn.commit()
  dbenv.close(dbi)

proc initSeqsDB(dbenv: LMDBEnv) =
  let txn = dbenv.newTxn()
  let dbi = txn.dbiOpen("seqs", flags=CREATE)
  txn.commit()
  dbenv.close(dbi)

proc initDBs(dbenv: LMDBEnv, compressSeqs: bool = true) =
  initInfoDB(dbenv, compressSeqs=compressSeqs)
  initSeqsDB(dbenv)

proc putZstdDict(dbenv: LMDBEnv, dict: string) =
  let txn = dbenv.newTxn()
  let dbi = txn.dbiOpen(INFO_DB_NAME, flags=CREATE)
  try:
    txn.put(dbi, "zstd_dictionary", dict)
    txn.commit()
  except Exception as ex:
    stderr.writeLine(fmt"Could not write dict to LMDB. Error: {ex.msg} ({ex.name})")
    txn.abort()
    raise ex
  finally:
    dbenv.close(dbi)

proc getZstdDict(dbenv: LMDBEnv): string =
  let txn = dbenv.newTxn()
  let dbi = txn.dbiOpen(INFO_DB_NAME, 0)
  try:
    return txn.get(dbi, "zstd_dictionary")
  except Exception as ex:
    stderr.writeLine(fmt"No Zstd dict could be read from LMDB. Error: {ex.msg} ({ex.name})")
    return ""
  finally:
    txn.abort()
    dbenv.close(dbi)

proc areSeqsCompressed(dbenv: LMDBEnv): bool =
  let txn = dbenv.newTxn()
  let dbi = txn.dbiOpen(INFO_DB_NAME, 0)
  try:
    return txn.get(dbi, "is_compressed") == "true"
  except Exception as ex:
    stderr.writeLine(fmt"No Zstd dict could be read from LMDB. Error: {ex.msg} ({ex.name})")
    return false
  finally:
    txn.abort()
    dbenv.close(dbi)

proc getSeq(dbenv: LMDBEnv, seqid: string, dict: string = "", isCompressed: bool = true): string =
  let txn = dbenv.newTxn()
  let dbi = txn.dbiOpen("", 0)
  try:
    if isCompressed:
      var compressedSeq = txn.get(dbi, seqid)
      var dctx = new_decompress_context()
      var decompressedSeq: seq[byte]
      if dict != "":
        decompressedSeq = decompress(dctx, compressedSeq, dict=dict)
      else:
        decompressedSeq = decompress(dctx, compressedSeq)
      discard free_context(dctx)
      return toStrBuf(decompressedSeq)
    else:
      return txn.get(dbi, seqid)
  except Exception as ex:
    stderr.writeLine(fmt"Could not get sequence for '{seqid}' from LMDB. Error: {ex.msg}")
    return ""
  finally:
    txn.abort()
    dbenv.close(dbi)

proc writeFastaSeqToStdout(seqid: string, sequence: string) =
  if sequence != "":
    stdout.writeLine(fmt">{seqid}")
    stdout.writeLine(sequence)

proc getLMDBSeqWriteToStdout(dbenv: LMDBEnv, seqid: string, dict: string, isCompressed: bool = true) =
  writeFastaSeqToStdout(seqid, getSeq(dbenv, seqid, dict, isCompressed))

proc toLMDB(
    dbpath: string, 
    zstdDict: string = "",
    mapSize: uint = 10485760 * 1024,
    overwriteDB: bool = false,
    compressSeqs: bool = true,
    level: int = 3) =
  var useExistingDict = false
  if not overwriteDB and dirExists(dbpath):
    logger.log(lvlInfo, fmt"Trying to read zstd dictionary from existing LMDB at '{dbpath}'")
    useExistingDict = true
  if overwriteDB or not dirExists(dbpath):
    logger.log(lvlInfo, fmt"Creating DB at '{dbpath}'. Removing 'lock.mdb' and 'data.mdb' if present.")
    flush_database_dir(dbpath)
  var dbenv = newLMDBEnv(dbpath, openflags=MAPASYNC or NOSYNC, maxdbs=10)
  discard envSetMapsize(dbenv, mapSize)
  logger.log(lvlInfo, fmt"map size set = {mapSize}")
  var dict: string = ""
  if useExistingDict:
    dict = getZstdDict(dbenv)
  else:
    initDBs(dbenv, compressSeqs=compressSeqs)
    logger.log(lvlInfo, "Initialized DBs")
  
  var f = xopen[GzFile]("-")
  defer: f.close()
  var rec: FastxRecord
  
  if dict == "" or not useExistingDict or overwriteDB:
    logger.log(lvlInfo, fmt"No dict read from DB. zstdDict={zstdDict}")
    if zstdDict != "" and fileExists(zstdDict):
      dict = readFile(zstdDict)
      putZstdDict(dbenv, dict)
      logger.log(lvlInfo, fmt"Saved zstd dictionary from '{zstdDict}' to LMDB")
    else:
      logger.log(lvlInfo, "No zstd dictionary!")
      dict = ""
  
  logger.log(lvlInfo, fmt"Reading records from stdin and saving to LMDB '{dbpath}'")
  var count = 0
  var val: string
  while f.readFastx(rec):
    if useExistingDict:
      let txn = dbenv.newTxn()
      let dbi = txn.dbiOpen("", 0)
      try:
        val = txn.get(dbi, getHeader(rec.name, rec.comment))
      except:
        spawn saveSeq(dbenv, dict, rec.name, rec.comment, rec.seq, compressSeqs, level)
      finally:
        txn.abort()
        dbenv.close(dbi)
    else:
      spawn saveSeq(dbenv, dict, rec.name, rec.comment, rec.seq, compressSeqs, level)
    
    count += 1
    # Memory usage keeps climbing as more values are put into the LMDB.
    # Keys and values put into the DB seem to be kept in memory through the 
    # LMDBEnv object. Recreating the LMDBEnv frees up memory and reduces max
    # memory usage.
    if count mod 300_000 == 0:
      threadpool.sync()
      dbenv.envClose()
      dbenv = newLMDBEnv(dbpath, openflags=MAPASYNC or NOSYNC, maxdbs=10)
      discard envSetMapsize(dbenv, mapSize)
  # end while
  threadpool.sync()
  dbenv.envClose()
  logger.log(lvlInfo, fmt"Read {count} records!")
  logger.log(lvlInfo, "DONE!")

proc fasta2lmdb(
    dbpath="./gisaidseqs", 
    mapSize: uint = 10485760 * 1024, 
    overwriteDB = false,
    seqids = "",
    zstdDict = "",
    compressSeqs: bool = true) =
  ## Read FASTA records from stdin into LMDB key-value database or get sequences from LMDB
  ##
  ## Expected usage to create an LMDB DB from a FASTA piped into fasta2lmdb:
  ##
  ## $ pixz -d < sequences_fasta_YYYY_mm_dd.tar.xz | tar -xOf - sequences.fasta | fasta2lmdb --dbpath ./gisaidseqs
  ##
  ## NOTE: train a Zstd dictionary on your sequences for better and faster compression and decompression of your sequences!
  ##
  ## Expected usage to retrieve sequences from LMDB DB to stdout:
  ##
  ## $ fasta2lmdb --dbpath /path/to/gisaidseqs --seqids seqids.txt > seqs.fasta
  ##
  ## where "seqids.txt" contains sequence IDs to retrieve; one per line
  if not isatty(stdin):
    toLMDB(dbpath, zstdDict, mapSize, overwriteDB, compressSeqs)
  else:
    if not seqids.fileExists():
      raise newException(Exception, fmt"No stdin stream present and file with sequence IDs ('{seqids}') does not exist!")
    logger.log(lvlInfo, fmt"Start fetch sequences from LMDB '{dbpath}' with IDs in '{seqids}'")
    let dbenv = newLMDBEnv(dbpath, maxdbs=10)
    let dict = getZstdDict(dbenv)
    let compressed = areSeqsCompressed(dbenv)
    for line in seqids.lines:
      if line == "":
        continue
      getLMDBSeqWriteToStdout(dbenv, line, dict, compressed)
    dbenv.envClose()
    logger.log(lvlInfo, "DONE!")

dispatch(fasta2lmdb)