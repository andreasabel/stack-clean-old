{-# LANGUAGE CPP #-}

import Control.Monad.Extra
import Data.List.Extra
import SimpleCmd
#if MIN_VERSION_simple_cmd(0,2,1)
  hiding (ifM)
#endif
import SimpleCmdArgs
import System.Directory
import System.FilePath

import Paths_stack_clean_old (version)

main :: IO ()
main = do
  simpleCmdArgs (Just version) "Stack clean up tool"
    "Cleans away old stack-work builds (and pending: stack snapshots) to recover diskspace." $
    -- subcommands
    -- [ Subcommand "project" "purge older builds in .stack-work/install" $
      cleanStackWork <$> keepOption "number of project builds per ghc version" <*> optional (strArg "PROJECTDIR")
    -- , Subcommand "snapshots" "purge older ~/.stack/snapshots" $
    --   cleanSnapshots <$> keepOption "number of dozens of snapshot builds per ghc version"
    -- ]
  where
    keepOption hlp = positive <$> (optionalWith auto 'k' "keep" "INT" hlp 5)

    positive :: Int -> Int
    positive n = if n > 0 then n else error' "Must be positive integer"

cleanStackWork :: Int -> Maybe FilePath -> IO ()
cleanStackWork keep mdir = do
  whenJust mdir $ \ dir -> setCurrentDirectory dir
  switchToSystemDirUnder ".stack-work/install"
  cleanAwayOldBuilds $ keep

-- -- Disabled until we track deps between snapshot dirs!
-- cleanSnapshots :: Int -> IO ()
-- cleanSnapshots keep = do
--   home <- getHomeDirectory
--   switchToSystemDirUnder $ home </> ".stack/snapshots"
--   cleanAwayOldBuilds $ keep * 10

switchToSystemDirUnder :: FilePath -> IO ()
switchToSystemDirUnder dir = do
  ifM (doesDirectoryExist dir)
    (setCurrentDirectory dir)
    (error' $ dir ++ "not found")
  systems <- listDirectory "."
  let system = case systems of
        [] -> error' $ "No OS system in " ++ dir
        [sys] -> sys
        _ -> error' "More than one OS systems found " ++ dir ++ " (unsupported)"
  setCurrentDirectory system

cleanAwayOldBuilds :: Int -- ^ number of snapshots to keep per ghc version
                   -> IO ()
cleanAwayOldBuilds keep = do
  -- sort and then group by ghc version
  dirs <- sortOn takeFileName . lines <$> shell ( unwords $ "ls" : ["-d", "*/*"])
  let ghcs = groupOn takeFileName dirs
  mapM_ removeOlder ghcs
  where
    removeOlder :: [FilePath] -> IO ()
    removeOlder dirs = do
      oldfiles <- drop keep . reverse <$> sortedByAge
      mapM_ (removeDirectoryRecursive . takeDirectory) oldfiles
      unless (null oldfiles) $
        putStrLn $ show (length oldfiles) ++ " dirs removed"
      where
        sortedByAge = do
          fileTimes <- mapM newestTimeStamp dirs
          return $ map fst $ sortOn snd fileTimes

        newestTimeStamp dir = do
          withCurrentDirectory dir $ do
            files <- listDirectory "."
            timestamp <- maximum <$> mapM getModificationTime files
            return (dir, timestamp)
