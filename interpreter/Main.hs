module Main (main) where

import System.IO (stdin)
import System.Environment (getArgs)
import qualified Data.ByteString.Lazy.Char8 as BS

import Lang.LAMA.Parse

type Verbosity = Int

putStrV :: Verbosity -> String -> IO ()
putStrV v s = if v > 1 then putStrLn s else return ()

runFile :: Verbosity -> FilePath -> IO ()
runFile v f = putStrLn f >> BS.readFile f >>= run v

run :: Verbosity -> BS.ByteString -> IO ()
run v inp = case parseLAMA inp of
  Left (ParseError pe) -> do
    putStrLn "Parse failed..."
    putStrLn pe
  Left (StaticError se) -> do
    putStrLn $ "Conversion failed:"
    putStrLn se
  Right concTree -> putStrV v $ show concTree

main :: IO ()
main = do args <- getArgs
          case args of
            [] -> BS.hGetContents stdin >>= run 2
            "-s":fs -> mapM_ (runFile 0) fs
            fs -> mapM_ (runFile 2) fs
