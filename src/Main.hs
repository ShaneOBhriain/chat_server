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
  mainLoop sock listeningChan 0

type Msg = (Int, String)

mainLoop :: Socket -> Chan Msg -> Int -> IO ()
mainLoop sock chan msgNum = do
  putStr "loop in mainLoop\n"
  conn <- accept sock
  forkIO (runConn conn chan msgNum)
  -- $! = strict function application
  mainLoop sock chan $! msgNum + 1

-- offers lobby for the user to choose their chan
runConn :: (Socket, SockAddr) -> Chan Msg -> Int -> IO()
runConn (sock, address) chan msgNum = do
  hdl <- socketToHandle sock ReadWriteMode
  hSetBuffering hdl NoBuffering
  message <- fmap init (hGetLine hdl)
  processMessage message address hdl

processMessage :: String -> SockAddr -> Handle -> IO()
processMessage msg address handle
    | msg == "KILL_SERVICE\n" = putStr "Killing service"
    | substring "HELO_text" msg = sendHeloText address handle
    | substring "CHAT:" msg = putStr "Handling CHAT message"
    | substring "DISCONNECT" msg = putStr "Disconnecting"
    | substring "LEAVE_CHATROOM" msg = putStr "Joining chatroom"
    | substring "JOIN_CHATROOM" msg = putStr "Joining chatroom"
    | otherwise = putStr "ELSE I GUESS"

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
