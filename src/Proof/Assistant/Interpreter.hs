{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeSynonymInstances #-}
module Proof.Assistant.Interpreter where

import Control.Concurrent.Async
import Control.Monad (forever)
import Data.ByteString (ByteString)
import Data.Coerce
import System.Directory
import System.FilePath
import System.Process
import Telegram.Bot.API (ChatId (..))

import Agda.Interaction.State

import qualified Data.ByteString.Char8 as BS8

import Proof.Assistant.Agda
import Proof.Assistant.Helpers
import Proof.Assistant.Request
import Proof.Assistant.ResourceLimit
import Proof.Assistant.Response
import Proof.Assistant.Settings
import Proof.Assistant.State
import Proof.Assistant.Transport

runInterpreter :: (Interpreter state settings) => BotState -> state -> IO ()
runInterpreter botState is = forever $ do
  incomingMessage <- readInput (getSettings is)
  response <- interpretSafe is incomingMessage
  let telegramResponse = makeTelegramResponse incomingMessage response
  writeOutput telegramResponse botState

class Interpreter state settings | state -> settings where
  interpretSafe :: state -> InterpreterRequest -> IO ByteString
  getSettings :: state -> InterpreterState settings

instance Interpreter InternalState InternalInterpreterSettings  where
  interpretSafe _ _ = pure "TBD"
  getSettings = id

instance Interpreter AgdaState AgdaSettings where
  interpretSafe state request = callAgda state request
  getSettings state = interpreterState state

instance Interpreter ExternalState ExternalInterpreterSettings where
  interpretSafe is request = do
    let settings' = settings is
    tmpFilePath <- refreshTmpFile settings' request
    callExternalInterpreter settings' tmpFilePath
  getSettings = id
    
-- ** External Interpreter

refreshTmpFile :: ExternalInterpreterSettings -> InterpreterRequest -> IO (FilePath, FilePath)
refreshTmpFile
  ExternalInterpreterSettings{tempFilePrefix, fileExtension}
  InterpreterRequest{interpreterRequestTelegramChatId, interpreterRequestMessage} = do
    tmpDir <- getTemporaryDirectory
    let chatIdToString = show . coerce @_ @Integer
        tmpFilepath = tmpDir
          </> tempFilePrefix
          <> chatIdToString interpreterRequestTelegramChatId
          <.> fileExtension
        createFile = do
          BS8.writeFile tmpFilepath $ dropCommand interpreterRequestMessage
          pure (tmpDir, tmpFilepath)
    exist <- doesFileExist tmpFilepath
    if (not exist)
      then createFile
      else removeFile tmpFilepath >> createFile

callExternalInterpreter
  :: ExternalInterpreterSettings -> (FilePath, FilePath) -> IO ByteString
callExternalInterpreter ExternalInterpreterSettings{..} (dir, path)
  = withCurrentDirectory dir $ do
      contents <- readFile path
      let asyncExecutable = do
            setPriority priority
            (exitCode, stdout, stderr) <- readProcessWithExitCode (t2s executable) [t2s args] contents
            putStrLn $ show exitCode <> " " <> stderr
            pure $ BS8.pack $ unlines [stdout, stderr]
          asyncTimer = asyncWait time
      eresult <- race asyncTimer asyncExecutable
      case eresult of
        Left ()  -> pure "Time limit exceeded"
        Right bs -> pure bs
