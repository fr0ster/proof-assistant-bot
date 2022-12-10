{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
module Proof.Assistant.Response where

import Data.ByteString (ByteString)
import Data.Text.Encoding (decodeUtf8)
import Telegram.Bot.API
  (ChatId, MessageId, ParseMode (..), SendMessageRequest (..), SomeChatId (..))

import Proof.Assistant.Request

data InterpreterResponse = InterpreterResponse
  { interpreterResponseTelegramChatId :: !ChatId
  , interpreterResponseTelegramMessageId :: !MessageId
  , interpreterResponseResponse :: !ByteString
  }

toSendMessageRequest :: Bool -> InterpreterResponse -> SendMessageRequest
toSendMessageRequest isMonospace InterpreterResponse{..} = SendMessageRequest
  { sendMessageChatId                   = SomeChatId interpreterResponseTelegramChatId
  , sendMessageText
      = if isMonospace
        then "```\n" <> decodeUtf8 interpreterResponseResponse <> "\n```\n"
        else decodeUtf8 interpreterResponseResponse <> "\n"
  , sendMessageParseMode                = if isMonospace then Just MarkdownV2 else Nothing
  , sendMessageEntities                 = Nothing
  , sendMessageDisableWebPagePreview    = Nothing
  , sendMessageDisableNotification      = Nothing
  , sendMessageProtectContent           = Nothing
  , sendMessageReplyToMessageId         = Just interpreterResponseTelegramMessageId
  , sendMessageAllowSendingWithoutReply = Nothing
  , sendMessageReplyMarkup              = Nothing
  }

makeTelegramResponse :: InterpreterRequest -> ByteString -> InterpreterResponse
makeTelegramResponse InterpreterRequest{..} response =
  InterpreterResponse
    { interpreterResponseTelegramChatId    = interpreterRequestTelegramChatId
    , interpreterResponseTelegramMessageId = interpreterRequestTelegramMessageId
    , interpreterResponseResponse          = response
    }
