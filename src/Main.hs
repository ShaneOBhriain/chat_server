-- Main.hs, final code
module Main where

import Data.List
import Data.IORef
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

  referenceList <- newIORef []

  -- this loop waits for connections, line 2 reads chan
  _ <- forkIO $ fix $ \loop -> do
    putStr "loop in main\n"
    (_, _) <- readChan listeningChan
    loop
  putStr "calling mainloop no idea why\n"
  mainLoop sock listeningChan 0 referenceList

type Msg = (Int, String)

-- stringChan :: Chan Msg-> String
-- stringChan (i s)= show i

mainLoop :: Socket -> Chan Msg -> Int -> IORef [(String, Chan Msg)]-> IO ()
mainLoop sock chan msgNum chanListRef = do
  conn <- accept sock
  hdl <- setHandle conn
  -- line above waits until join then runs line below
  forkIO (runConn conn hdl chan msgNum chanListRef)
  mainLoop sock chan (msgNum+1) chanListRef

setHandle :: (Socket,SockAddr) -> IO Handle
setHandle (sock,addr) = do
  hdl <- socketToHandle sock ReadWriteMode
  hSetBuffering hdl NoBuffering
  return hdl

getFirst :: (String, Chan Msg) -> String
getFirst (x,y) = x

getSecond :: (String, Chan Msg) -> Chan Msg
getSecond (x,y) = y

addToChanList :: String -> Chan Msg -> IORef [(String, Chan Msg)] -> IO ()
addToChanList newChanName myChan var = do
    val <- readIORef var
    let newVal = (newChanName,myChan):val
    writeIORef var newVal

-- offers lobby for the user to choose their chan
-- Parameters: Socket, Handle of socket, Current Chan, List of Existing Chans, List of existing chan names
runConn :: (Socket, SockAddr) -> Handle -> Chan Msg -> Int -> IORef [(String, Chan Msg)] -> IO()
runConn (sock, address) hdl chan msgNum chanListRef = do
  let broadcast msg = writeChan chan (msgNum, msg)
  message <- fmap init (hGetLine hdl)
  messageType <- processMessage message
  case messageType of
    0 -> hClose hdl
    1 -> sendHeloText address hdl
    2 -> do
          broadcast message
    3 -> putStrLn "Disconnecting"
    4 -> do
          putStrLn "Joining chatroom"
          let clientName = getClientName message
          let chatroomName = getChatroomName message
          theChanList <- readIORef chanListRef
          let myNewChan = lookup chatroomName theChanList
          case myNewChan of
            Nothing -> do
                        myChan <- newChan
                        putStrLn $ "Didnt find it [" ++ chatroomName ++"] in a lookup"
                        addToChanList chatroomName myChan chanListRef

                        reader <- forkIO $ fix $ \loop -> do
                          -- Read the next value from the Chan. Blocks when the channel is empty.
                          -- Since the read end of a channel is an MVar, this operation inherits fairness guarantees of MVars (e.g. threads blocked in this operation are woken up in FIFO order).
                            (nextNum, line) <- readChan myChan
                            when (msgNum /= nextNum) $ hPutStrLn hdl line
                            loop
                        hPutStrLn hdl $ printJoinedRoom chatroomName address
                        runConn (sock, address) hdl myChan msgNum chanListRef
            Just x -> do
                        myChan <- dupChan x
                        reader <- forkIO $ fix $ \loop -> do
                          -- Read the next value from the Chan. Blocks when the channel is empty.
                          -- Since the read end of a channel is an MVar, this operation inherits fairness guarantees of MVars (e.g. threads blocked in this operation are woken up in FIFO order).
                            (nextNum, line) <- readChan myChan
                            when (msgNum /= nextNum) $ hPutStrLn hdl line
                            loop
                        hPutStrLn hdl $ printJoinedRoom chatroomName address
                        runConn (sock, address) hdl myChan msgNum chanListRef
    5 -> putStrLn "Leaving chatroom"
    6 -> do
          putStrLn "broadcasting message"
          broadcast message
  putStrLn "Got to bottom"
  runConn (sock, address) hdl chan msgNum chanListRef

printJoinedRoom :: String -> SockAddr -> String
printJoinedRoom roomName address = do
                                    let ip = getSockAddress address
                                    let port = getSockPort address
                                    "JOINED_CHATROOM: " ++ roomName ++ "\nSERVER_IP:" ++ ip ++"\nPORT: "++ port ++ "\nROOM_REF: [integer that uniquely identifies chat room on server]\nJOIN_ID: [integer that uniquely identifies client joining]"

getClientName :: String -> String
getClientName x = tail $ reverse $ take (unpackJust (elemIndex ':' $ reverse x)) $ reverse x

getFirstLine :: String -> String
getFirstLine x = take (unpackJust (elemIndex '\\' $ x)) $ x

getChatroomName :: String -> String
getChatroomName x = tail $ reverse $ take (unpackJust (elemIndex ':' $ reverse (getFirstLine x))) $ reverse (getFirstLine x)

-- joinChatroom :: String -> [Chan Msg] -> ()

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

unpackJustString :: Maybe String -> String
unpackJustString (Just a) = a
unpackJustString _  = "Nothing"

unpackJust :: Maybe Int -> Int
unpackJust (Just a) = a
unpackJust _  = 404

getSockPort :: SockAddr -> String
getSockPort x = tail $ drop (unpackJust (elemIndex ':' $ show x)) $ show x

getSockAddress :: SockAddr -> String
getSockAddress x = take (unpackJust (elemIndex ':' $ show x)) $ show x


sendHeloText :: SockAddr -> Handle -> IO()
sendHeloText address hdl = hPutStr hdl ("HELO text\nIP: "  ++ getSockAddress address ++ "\n" ++ "Port: " ++ getSockPort address ++ "\nStudentID: 13324607\n")
