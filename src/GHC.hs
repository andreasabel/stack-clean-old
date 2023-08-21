module GHC (
  listGhcInstallation,
  removeGhcMinorInstallation,
  removeGhcVersionInstallation,
  sizeGhcInstalls
  )
where

import Control.Monad.Extra
import Data.List.Extra
import Data.Version.Extra
import SimpleCmd
import System.FilePath

import Directories (getStackSubdir, globDirs, switchToSystemDirUnder)
import qualified Remove
import Types
import Versions

getStackProgramsDir :: IO FilePath
getStackProgramsDir =
  getStackSubdir "programs"

sizeGhcInstalls :: Bool -> IO ()
sizeGhcInstalls nothuman = do
  programs <- getStackProgramsDir
  cmd_ "du" $ ["-h" | not nothuman] ++ ["-s", programs]

setStackProgramsDir :: Maybe String -> IO ()
setStackProgramsDir msystem =
  getStackProgramsDir >>= switchToSystemDirUnder msystem

getGhcInstallDirs :: Maybe Version -> Maybe String -> IO [FilePath]
getGhcInstallDirs mghcver msystem = do
  setStackProgramsDir msystem
  dirs <- map dropTrailingSlash <$> globDirs ("ghc-" ++ matchVersion)
  return $ sortOn ghcInstallVersion dirs
  where
    -- 'globDirs' may return something like @["ghc-9.4.5/"]@, so, need to clean trailing slash.
    dropTrailingSlash = dropWhileEnd (\ c -> c == '/' || c == '\\')
    matchVersion =
      case mghcver of
        Nothing -> "*"
        Just ver ->
          showVersion ver ++ if isMajorVersion ver then "*" else ""

ghcInstallVersion :: FilePath -> Version
ghcInstallVersion =
  readVersion . takeWhileEnd (/= '-') .  dropSuffix ".temp"

listGhcInstallation :: Maybe Version -> Maybe String -> IO ()
listGhcInstallation mghcver msystem = do
  dirs <- getGhcInstallDirs mghcver msystem
  mapM_ putStrLn $ case mghcver of
    Nothing -> dirs
    Just ghcver -> filter ((== ghcver) . (if isMajorVersion ghcver then majorVersion else id) . ghcInstallVersion) dirs

removeGhcVersionInstallation :: Deletion -> Version -> Maybe String -> IO ()
removeGhcVersionInstallation deletion ghcver msystem = do
  installs <- getGhcInstallDirs (Just ghcver) msystem
  case installs of
    [] -> putStrLn $ "stack ghc compiler version " ++ showVersion ghcver ++ " not found"
    [g] | not (isMajorVersion ghcver) -> doRemoveGhcVersion deletion g
    gs -> if isMajorVersion ghcver then do
      Remove.prompt deletion ("all stack ghc " ++ showVersion ghcver ++ " installations: ")
      mapM_ (doRemoveGhcVersion deletion) gs
      else error' "more than one match found!!"

removeGhcMinorInstallation :: Deletion -> Maybe Version -> Maybe String
                           -> IO ()
removeGhcMinorInstallation deletion mghcver msystem = do
  dirs <- getGhcInstallDirs (majorVersion <$> mghcver) msystem
  case mghcver of
    Nothing -> do
      let majors = groupOn (majorVersion . ghcInstallVersion) dirs
      forM_ majors $ \ minors ->
        forM_ (init minors) $ doRemoveGhcVersion deletion
    Just ghcver -> do
      let minors = filter ((< ghcver) . ghcInstallVersion) dirs
      forM_ minors $ doRemoveGhcVersion deletion

doRemoveGhcVersion :: Deletion -> FilePath -> IO ()
doRemoveGhcVersion deletion ghcinst = do
  Remove.doRemoveDirectory deletion ghcinst
  Remove.removeFile deletion (ghcinst <.> "installed")
  putStrLn $ ghcinst ++ " compiler " ++ (if isDelete deletion then "" else "would be ") ++ "removed"
