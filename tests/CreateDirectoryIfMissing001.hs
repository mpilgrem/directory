{-# LANGUAGE CPP #-}
module CreateDirectoryIfMissing001 where
#include "util.inl"
import System.Directory
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import qualified Control.Exception as E
import Control.Monad (replicateM_)
import System.FilePath ((</>), addTrailingPathSeparator)
import System.IO (hFlush, stdout)
import System.IO.Error(isAlreadyExistsError, isDoesNotExistError,
                       isPermissionError)
#ifndef mingw32_HOST_OS
import GHC.IO.Exception (IOErrorType(InappropriateType))
import System.IO.Error(ioeGetErrorType)
#endif

main :: TestEnv -> IO ()
main _t = do

  createDirectoryIfMissing False testdir
  cleanup

  T(expectIOErrorType) () isDoesNotExistError $
    createDirectoryIfMissing False testdir_a

  createDirectoryIfMissing True  testdir_a
  createDirectoryIfMissing False testdir_a
  createDirectoryIfMissing False (addTrailingPathSeparator testdir_a)
  cleanup

  createDirectoryIfMissing True  (addTrailingPathSeparator testdir_a)

  putStrLn "testing for race conditions ..."
  hFlush stdout
  raceCheck1
  raceCheck2
  putStrLn "done."
  hFlush stdout
  cleanup

  writeFile testdir testdir
  T(expectIOErrorType) () isAlreadyExistsError $
    createDirectoryIfMissing False testdir
  removeFile testdir
  cleanup

  writeFile testdir testdir
  T(expectIOErrorType) () isNotADirectoryError $
    createDirectoryIfMissing True testdir_a
  removeFile testdir
  cleanup

  where

    testdir = "createDirectoryIfMissing001.d"
    testdir_a = testdir </> "a"

    -- Look for race conditions (bug #2808 on GHC Trac).  This fails with
    -- +RTS -N2 and directory 1.0.0.2.
    raceCheck1 = do
      m <- newEmptyMVar
      _ <- forkIO $ do
        replicateM_ 10000 create
        putMVar m ()
      _ <- forkIO $ do
        replicateM_ 10000 cleanup
        putMVar m ()
      replicateM_ 2 (takeMVar m)

    -- This test fails on Windows (see bug #2924 on GHC Trac):
    raceCheck2 = do
      m <- newEmptyMVar
      replicateM_ 4 $
        forkIO $ do
          replicateM_ 10000 $ do
            create
            cleanup
          putMVar m ()
      replicateM_ 4 (takeMVar m)

    -- createDirectoryIfMissing is allowed to fail with isDoesNotExistError if
    -- another process/thread removes one of the directories during the process
    -- of creating the hierarchy.
    --
    -- It is also allowed to fail with permission errors
    -- (see bug #2924 on GHC Trac)
    create =
      createDirectoryIfMissing True testdir_a `E.catch` \ e ->
      if isDoesNotExistError e || isPermissionError e
      then return ()
      else ioError e

    cleanup = removeDirectoryRecursive testdir `catchAny` \ _ -> return ()

    catchAny :: IO a -> (E.SomeException -> IO a) -> IO a
    catchAny = E.catch

#ifdef mingw32_HOST_OS
    isNotADirectoryError = isAlreadyExistsError
#else
    isNotADirectoryError e = case ioeGetErrorType e of
      InappropriateType -> True
      _                 -> False
#endif