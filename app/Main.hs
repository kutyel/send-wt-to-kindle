{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson (FromJSON (..), Options (..), defaultOptions, genericParseJSON)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import Data.Char (toUpper)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Calendar (addGregorianMonthsClip)
import Data.Time.Clock (getCurrentTime, utctDay)
import Data.Time.Format (formatTime, defaultTimeLocale)
import GHC.Generics (Generic)
import Network.HTTP.Simple (getResponseBody, httpLBS, parseRequest)
import Network.Mail.Mime
  ( Address (..),
    Mail (..),
    addAttachmentBS,
    emptyMail,
    plainPart,
  )
import Network.Mail.SMTP (sendMailWithLoginSTARTTLS')
import System.Environment (getEnv, lookupEnv)
import System.FilePath (takeFileName)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

monthsAhead :: Integer
monthsAhead = 2

-- ---------------------------------------------------------------------------
-- JSON response types
-- ---------------------------------------------------------------------------

-- Field names match JSON keys exactly → auto-derived
newtype FileInfo = FileInfo {url :: Text} deriving (Generic, FromJSON)

newtype EpubEntry = EpubEntry {file :: FileInfo} deriving (Generic, FromJSON)

-- JSON keys are uppercase ("EPUB", "S") → genericParseJSON with toUpper
newtype LangFiles = LangFiles {epub :: [EpubEntry]} deriving (Generic)

instance FromJSON LangFiles where
  parseJSON = genericParseJSON defaultOptions {fieldLabelModifier = map toUpper}

newtype FilesMap = FilesMap {s :: LangFiles} deriving (Generic)

instance FromJSON FilesMap where
  parseJSON = genericParseJSON defaultOptions {fieldLabelModifier = map toUpper}

-- Field names match JSON keys exactly → auto-derived
data ApiResponse = ApiResponse
  { files :: FilesMap,
    formattedDate :: Maybe Text
  }
  deriving (Generic, FromJSON)

-- ---------------------------------------------------------------------------
-- Date computation
-- ---------------------------------------------------------------------------

-- | Return the issue code (YYYYMM) for monthsAhead months from today.
getIssueCode :: IO String
getIssueCode = do
  today <- utctDay <$> getCurrentTime
  let future = addGregorianMonthsClip monthsAhead today
  pure $ formatTime defaultTimeLocale "%Y%m" future

-- ---------------------------------------------------------------------------
-- HTTP helpers
-- ---------------------------------------------------------------------------

apiUrl :: String -> String
apiUrl code =
  "https://b.jw-cdn.org/apis/pub-media/GETPUBMEDIALINKS"
    ++ "?issue="
    ++ code
    ++ "&output=json&pub=w&fileformat=EPUB&alllangs=0&langwritten=S&txtCMSLang=S"

-- | Call the jw.org pub-media API and return the EPUB download URL and filename.
fetchEpubUrl :: String -> IO (Maybe (String, String))
fetchEpubUrl issueCode = do
  putStrLn $ "[*] Fetching metadata for issue " ++ issueCode ++ "..."
  req <- parseRequest (apiUrl issueCode)
  resp <- httpLBS req
  case Aeson.eitherDecode (getResponseBody resp) of
    Left err -> do
      putStrLn $ "    JSON parse error: " ++ err
      pure Nothing
    Right apiResp -> do
      let entries = epub (s (files apiResp))
      case entries of
        [] -> do
          putStrLn $ "    No EPUB found for issue " ++ issueCode ++ ", skipping."
          pure Nothing
        (entry : _) -> do
          let epubUrl = T.unpack (url (file entry))
              filename = takeFileName epubUrl
              date = maybe issueCode T.unpack (formattedDate apiResp)
          putStrLn $ "    Found: " ++ date ++ " -> " ++ filename
          pure $ Just (epubUrl, filename)

-- | Download the EPUB file and return its contents.
downloadEpub :: String -> IO BL.ByteString
downloadEpub url' = do
  putStrLn $ "[*] Downloading " ++ url' ++ "..."
  req <- parseRequest url'
  resp <- httpLBS req
  let bytes = getResponseBody resp
      sizeKb = fromIntegral (BL.length bytes) `div` 1024 :: Int
  putStrLn $ "    Saved (" ++ show sizeKb ++ " KB)"
  pure bytes

-- ---------------------------------------------------------------------------
-- Email sending
-- ---------------------------------------------------------------------------

-- | Send an EPUB to the Kindle email address via SMTP with STARTTLS.
sendToKindle :: BL.ByteString -> String -> IO ()
sendToKindle epubBytes filename = do
  smtpServer <- getEnv "SMTP_SERVER"
  smtpPortStr <- lookupEnv "SMTP_PORT"
  senderEmail <- getEnv "SENDER_EMAIL"
  senderPass <- getEnv "SENDER_PASSWORD"
  kindleEmail <- getEnv "KINDLE_EMAIL"

  let port = maybe 587 read smtpPortStr :: Int
      from = Address Nothing (T.pack senderEmail)
      to = Address Nothing (T.pack kindleEmail)
      mail =
        addAttachmentBS
          "application/epub+zip"
          (T.pack filename)
          epubBytes
          (emptyMail from)
            { mailTo = [to],
              mailHeaders = [("Subject", "Watchtower")],
              mailParts = [[plainPart ""]]
            }

  putStrLn $ "[*] Sending " ++ filename ++ " to " ++ kindleEmail ++ "..."
  sendMailWithLoginSTARTTLS' smtpServer (fromIntegral port) senderEmail senderPass mail
  putStrLn "    Sent successfully!"

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  code <- getIssueCode
  putStrLn $ "Issue to process: " ++ code ++ "\n"

  result <- fetchEpubUrl code
  case result of
    Nothing -> fail "No EPUB available, exiting."
    Just (url', filename) -> do
      bytes <- downloadEpub url'
      sendToKindle bytes filename
      putStrLn "\nDone."
