-- Main.hs, final code
module Main where

import Data.List
import Network.Socket
import System.IO
import Data.List.Split
import Control.Exception
import Control.Concurrent
import Control.Monad (when)
import Control.Monad.Fix (fix)

main :: IO ()
main = do
  -- define streaming socket
  sock <- socket AF_INET Stream 0
  setSocketOption sock ReuseAddr 1
  -- bind :: socket -> socketAddress -> IO()
  bind sock (SockAddrInet 4242 iNADDR_ANY)
  -- listen :: socket -> MaxNumberOfQueueConnections
  listen sock 2
  listeningChan <- newChan
  -- this loop waits for connections, line 2 reads chan
  _ <- forkIO $ fix $ \loop -> do
    putStr "loop in main\n"
    (_, _) <- readChan listeningChan
    loop
  putStr "calling mainloop no idea why\n"
  mainLoop sock listeningChan

type Msg = (Int, String)

-- stringChan :: Chan Msg-> String
-- stringChan (i s)= show i

mainLoop :: Socket -> Chan Msg -> IO ()
mainLoop sock chan = do
  putStr "loop in mainLoop\n"
  conn <- accept sock
  -- line above waits until join then runs line below
  forkIO (runConn conn chan [])
  mainLoop sock chan



-- offers lobby for the user to choose their chan
runConn :: (Socket, SockAddr) -> Chan Msg -> [Chan Msg] -> IO()
runConn (sock, address) chan chanList = do
  hdl <- socketToHandle sock ReadWriteMode
  hSetBuffering hdl NoBuffering
  message <- fmap init (hGetLine hdl)
  messageType <- processMessage message
  case messageType of
    0 -> hClose hdl
    1 -> sendHeloText address hdl
    2 -> putStr "Handling CHAT message"
    3 -> putStr "Disconnecting"
    4 -> putStr "Joining chatroom"
    5 -> putStr "Leaving chatroom"
    6 -> putStr "handle other messages"

processMessage :: String -> IO Integer
processMessage msg
    | substring "KILL_SERVICE" msg = return 0
    | substring "HELO_text" msg = return 1
    | substring "CHAT:" msg = return 2
    | substring "DISCONNECT" msg = return 3
    | substring "JOIN_CHATROOM" msg = return 4
    | substring "LEAVE_CHATROOM" msg = return 5
    | otherwise = return 6

-- chatLoop :: (Socket, SockAddr) -> Chan Msg -> Int -> IO()


-- joinOrCreateChan :: String -> Chan Msg

substring :: String -> String -> Bool
substring (x:xs) [] = False
substring xs ys
    | prefix xs ys = True
    | substring xs (tail ys) = True
    | otherwise = False

prefix :: String -> String -> Bool
prefix [] ys = True
prefix (x:xs) [] = False
prefix (x:xs) (y:ys) = (x == y) && prefix xs ys

unpackJust :: Maybe Int -> Int
unpackJust (Just a) = a
unpackJust _  = 404

getSockPort :: SockAddr -> String
getSockPort x = tail $ drop (unpackJust (elemIndex ':' $ show x)) $ show x

getSockAddress :: SockAddr -> String
getSockAddress x = take (unpackJust (elemIndex ':' $ show x)) $ show x


sendHeloText :: SockAddr -> Handle -> IO()
sendHeloText address hdl = hPutStr hdl ("HELO text\nIP: "  ++ getSockAddress address ++ "\n" ++ "Port: " ++ getSockPort address ++ "\nStudentID: 13324607\n")
