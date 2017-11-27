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
  clientList <- newIORef []

  -- this loop waits for connections, line 2 reads chan
  _ <- forkIO $ fix $ \loop -> do
    (_, _) <- readChan listeningChan
    loop

  mainLoop sock listeningChan 0 1 clientList referenceList

type Msg = (Int, String)

mainLoop :: Socket -> Chan Msg -> Int -> Int -> IORef [(Int, String)] -> IORef [(Int, String, Chan Msg)]-> IO ()
mainLoop sock chan msgNum clientNum clientListRef chanListRef = do
  conn <- accept sock
  hdl <- setHandle conn
  -- line above waits until join then runs line below
  forkIO (runConn conn hdl chan msgNum clientNum clientListRef chanListRef)
  mainLoop sock chan (msgNum+1) (clientNum + 1) clientListRef chanListRef

addClient :: String -> IORef [(Int, String)] -> IO ()
addClient newClientName var = do
    val <- readIORef var
    let existingClient = getClientIdByName newClientName val
    case existingClient of
      Nothing -> do
        let ref = length val + 1
        let newVal = (ref, newClientName):val
        writeIORef var newVal
      Just x -> putStrLn "Already exists"

getClientIdByName :: String -> [(Int,String)] -> Maybe Int
getClientIdByName _ [] = Nothing
getClientIdByName key ((a,b):ys)
                  | key == b = Just a
                  | otherwise = getClientIdByName key ys

getClientNameById :: Int -> [(Int,String)] -> Maybe String
getClientNameById _ [] = Nothing
getClientNameById key ((a,b):ys)
                  | key == a = Just b
                  | otherwise = getClientNameById key ys

setHandle :: (Socket,SockAddr) -> IO Handle
setHandle (sock,addr) = do
  hdl <- socketToHandle sock ReadWriteMode
  hSetBuffering hdl NoBuffering
  return hdl

addToChanList :: String -> Chan Msg -> IORef [(Int, String, Chan Msg)] -> IO ()
addToChanList newChanName myChan var = do
    val <- readIORef var
    let ref = length val + 1
    let newVal = (ref, newChanName,myChan):val
    writeIORef var newVal

getChanByString :: String -> [(Int, String, Chan Msg)] -> Maybe (Chan Msg)
getChanByString name [] = Nothing
getChanByString name ((a,b,c):ys)
                  | name == b = Just $ c
                  | otherwise = getChanByString name ys

getChanRefByString :: String -> [(Int, String, Chan Msg)] -> Int
getChanRefByString name ((a,b,c):ys)
                  | name == b = a
                  | otherwise = getChanRefByString name ys

sendMessage :: String -> String -> Int -> Chan Msg -> IO()
sendMessage bigMessage clientName msgNum chan = do
                          putStrLn "SENDING MESSAGE"
                          let ref = getChatroomName bigMessage
                          -- let clientName = "client name"
                          let messageText = getClientName bigMessage
                          let message = "CHAT: " ++ ref ++"\nCLIENT_NAME: " ++ clientName ++ "\nMESSAGE: " ++ messageText
                          writeChan chan (msgNum, message)

-- offers lobby for the user to choose their chan
-- Parameters: Socket, Handle of socket, Current Chan, List of Existing Chans, List of existing chan names
runConn :: (Socket, SockAddr) -> Handle -> Chan Msg -> Int -> Int -> IORef [(Int, String)] -> IORef [(Int, String, Chan Msg)] -> IO()
runConn (sock, address) hdl chan msgNum clientNum clientListRef chanListRef = do
  message <- fmap init (hGetLine hdl)
  messageType <- processMessage message
  case messageType of
    0 -> hClose hdl
    1 -> sendHeloText address hdl
    2 -> do
          clientList <- readIORef clientListRef
          sendMessage message (unpackJustString $ getClientNameById clientNum clientList) msgNum chan
    3 -> do
          putStrLn "Disconnecting"
          hClose hdl
    4 -> do
          putStrLn "Joining chatroom"
          let clientName = getClientName message
          addClient clientName clientListRef
          let chatroomName = getChatroomName message
          theChanList <- readIORef chanListRef
          let myNewChan = getChanByString chatroomName theChanList
          case myNewChan of
            Nothing -> do
                        myChan <- newChan
                        putStrLn $ "Didnt find it [" ++ chatroomName ++"] in a lookup"
                        addToChanList chatroomName myChan chanListRef
                        theChanList <- readIORef chanListRef
                        hPutStrLn hdl $ printJoinedRoom chatroomName clientNum address theChanList
                        reader <- forkIO $ fix $ \loop -> do
                            putStrLn "Reader loop"
                            (nextNum, line) <- readChan myChan
                            when (msgNum /= nextNum) $ hPutStrLn hdl line
                            loop
                        runConn (sock, address) hdl myChan msgNum clientNum clientListRef chanListRef
            Just x -> do
                        myChan <- dupChan x
                        hPutStrLn hdl $ printJoinedRoom chatroomName clientNum address theChanList
                        reader <- forkIO $ fix $ \loop -> do
                            putStrLn "Reader loop"
                            (nextNum, line) <- readChan myChan
                            when (msgNum /= nextNum) $ hPutStrLn hdl line
                            loop
                        runConn (sock, address) hdl myChan msgNum clientNum clientListRef chanListRef
    5 -> do
          theChanList <- readIORef chanListRef
          hPutStrLn hdl $ printLeftRoom message clientNum
          myChan <- newChan
          runConn (sock, address) hdl myChan msgNum clientNum clientListRef chanListRef
    6 -> errorMessage hdl 1
  runConn (sock, address) hdl chan msgNum clientNum clientListRef chanListRef

errorMessage :: Handle -> Int -> IO()
errorMessage hdl 1 = hPutStr hdl "ERROR CODE: 1\nERROR_DESCRIPTION: Invalid input"
errorMessage hdl _ = hPutStr hdl "ERROR CODE: 1\nERROR_DESCRIPTION: Undefined error"

printJoinedRoom :: String -> Int -> SockAddr -> [(Int, String, Chan Msg)]  -> String
printJoinedRoom roomName clientNum address chanList = do
                                    let ip = getSockAddress address
                                    let port = getSockPort address
                                    let roomRef = show $ getChanRefByString roomName chanList
                                    let clientRef = show clientNum
                                    "JOINED_CHATROOM: " ++ roomName ++ "\nSERVER_IP:" ++ ip ++"\nPORT: "++ port ++ "\nROOM_REF: "++ roomRef ++ "\nJOIN_ID:" ++ clientRef

printLeftRoom :: String -> Int -> String
printLeftRoom msg clientNum = do
                              let roomRef = getChatroomName msg
                              let clientRef = show clientNum
                              "LEFT_CHATROOM: " ++ roomRef ++ "\nJOIN_ID:" ++ clientRef

getClientName :: String -> String
getClientName x = tail $ reverse $ take (unpackJust (elemIndex ':' $ reverse x)) $ reverse x

getFirstLine :: String -> String
getFirstLine x = take (unpackJust (elemIndex '\\' $ x)) $ x

getChatroomName :: String -> String
getChatroomName x = tail $ reverse $ take (unpackJust (elemIndex ':' $ reverse (getFirstLine x))) $ reverse (getFirstLine x)

processMessage :: String -> IO Integer
processMessage msg
    | substring "KILL_SERVICE" msg = return 0
    | substring "HELO_text" msg = return 1
    | substring "CHAT:" msg = return 2
    | substring "DISCONNECT" msg = return 3
    | substring "JOIN_CHATROOM" msg = return 4
    | substring "LEAVE_CHATROOM" msg = return 5
    | otherwise = return 6

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
