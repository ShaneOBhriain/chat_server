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

mainLoop :: Socket -> Chan Msg -> Int -> Int -> IORef [(Int, String, [Int])] -> IORef [(Int, String, Chan Msg)]-> IO ()
mainLoop sock chan msgNum clientNum clientListRef chanListRef = do
  conn <- accept sock
  hdl <- setHandle conn
  -- line above waits until join then runs line below
  forkIO (runConn conn hdl chan msgNum clientNum clientListRef chanListRef)
  mainLoop sock chan (msgNum+1) (clientNum + 1) clientListRef chanListRef

addClient :: String -> IORef [(Int, String, [Int])] -> IO ()
addClient newClientName var = do
    val <- readIORef var
    let existingClient = getClientIdByName newClientName val
    case existingClient of
      Nothing -> do
        let ref = length val + 1
        let newVal = (ref, newClientName, []):val
        writeIORef var newVal
      Just x -> putStrLn "Already exists"


deleteN :: Int -> [a] -> [a]
deleteN _ []     = []
deleteN i (a:as)
   | i == 0    = as
   | otherwise = a : deleteN (i-1) as

getClientRef :: (Int,String,[Int]) -> Int
getClientRef (a,b,c) = a

clientInRoom :: (Int,String,[Int]) -> Int -> Bool
clientInRoom (a,b,c) roomRef = elem roomRef c

addToClientRoomList :: Int -> Int -> IORef [(Int, String, [Int])] -> IO()
addToClientRoomList joinId roomId clientListRef = do
  clientList <- readIORef clientListRef
  let indexOfClientToEdit = unpackJustInt $ elemIndex joinId (map getClientRef clientList)
  let (a,b,c) = clientList !! indexOfClientToEdit
  let newClient = (a,b,roomId:c)
  let newClientList = deleteN indexOfClientToEdit clientList
  let finalClientList = newClient:newClientList
  writeIORef clientListRef finalClientList

removeFromClientRoomList :: Int -> Int -> IORef [(Int, String, [Int])] -> IO()
removeFromClientRoomList joinId roomId clientListRef = do
  clientList <- readIORef clientListRef
  let indexOfClientToEdit = unpackJustInt $ elemIndex joinId (map getClientRef clientList)
  let (a,b,c) = clientList !! indexOfClientToEdit
  let newClientList = deleteN indexOfClientToEdit clientList

  if elem roomId c then do
    let newC = deleteN (unpackJustInt $ elemIndex roomId (map getClientRef clientList)) c
    let newClient = (a,b,newC)
    let finalClientList = newClient:newClientList
    writeIORef clientListRef finalClientList
  else putStrLn "Tried to leave chat but wasn't a member of the room."

getClientById :: Int -> [(Int, String, [Int])] -> (Int,String,[Int])
getClientById _ [] = (999,"Failed",[])
getClientById ref ((a,b,c):ys)
              | ref == a = (a,b,c)
              | otherwise = getClientById ref ys

getClientIdByName :: String -> [(Int,String,[Int])] -> Maybe Int
getClientIdByName _ [] = Nothing
getClientIdByName key ((a,b,c):ys)
                  | key == b = Just a
                  | otherwise = getClientIdByName key ys

getClientNameById :: Int -> [(Int,String,[Int])] -> Maybe String
getClientNameById _ [] = Nothing
getClientNameById key ((a,b,c):ys)
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

getChanByRef :: Int -> [(Int, String, Chan Msg)] -> Maybe (Chan Msg)
getChanByRef ref [] = Nothing
getChanByRef ref ((a,b,c):ys)
                  | ref == a = Just $ c
                  | otherwise = getChanByRef ref ys

getChanRefByString :: String -> [(Int, String, Chan Msg)] -> Int
getChanRefByString name ((a,b,c):ys)
                  | name == b = a
                  | otherwise = getChanRefByString name ys

sendMessage :: String -> Int -> Chan Msg -> IO()
sendMessage bigMessage msgNum chan = writeChan chan (msgNum, unlines (head (lines bigMessage) : tail (tail (lines bigMessage))) )

errorCheckMessage :: Integer -> [String] -> Bool
errorCheckMessage 2 l = [getCommand x | x <- l] == ["CHAT","JOIN_ID", "CLIENT_NAME","MESSAGE"]
errorCheckMessage 4 l = [getCommand x | x <- l] == ["JOIN_CHATROOM","CLIENT_IP", "PORT","CLIENT_NAME"]
errorCheckMessage _ _ = True

processMessage :: String -> IO Integer
processMessage msg
    | "KILL_SERVICE" == msg = return 0
    | "HELO_text" == msg = return 1
    | "CHAT:" == msg = return 2
    | "DISCONNECT" == msg = return 3
    | "JOIN_CHATROOM" == msg = return 4
    | "LEAVE_CHATROOM" == msg = return 5
    | otherwise = return 6

runConn :: (Socket, SockAddr) -> Handle -> Chan Msg -> Int -> Int -> IORef [(Int, String, [Int])] -> IORef [(Int, String, Chan Msg)] -> IO()
runConn (sock, address) hdl chan msgNum clientNum clientListRef chanListRef = do
  message <- fmap init (hGetLine hdl)
  messageType <- processMessage $ getCommand message
  putStrLn $ "Message Type: " ++ (show messageType)
  putStrLn message
  putStrLn $ show (length $ lines message)
  putStrLn $ show (lines message)
  putStrLn $ show $ [getCommand x | x <- lines message]
  let isValid = errorCheckMessage messageType $ lines message

  if isValid then do
      case messageType of
        0 -> hClose hdl
        1 -> sendHeloText address hdl
        2 -> do
              theClientList <- readIORef clientListRef
              theChanList <- readIORef chanListRef
              let chanRef = read (dropCommand $ head $ lines message)::Int
              let receivingChan = unpackJustChan $ getChanByRef chanRef theChanList
              let client = getClientById clientNum theClientList
              if clientInRoom client chanRef then sendMessage message msgNum receivingChan
              else errorMessage hdl 4
        3 -> do
              putStrLn "Disconnecting"
              hClose hdl
        4 -> do
              putStrLn "Joining chatroom"
              let clientName = dropCommand $ getFirstLine $ reverse message
              let chatroomName = dropCommand (getFirstLine message)

              addClient clientName clientListRef
              theChanList <- readIORef chanListRef
              let myNewChan = getChanByString chatroomName theChanList
              case myNewChan of
                Nothing -> do
                            myChan <- newChan
                            addToChanList chatroomName myChan chanListRef
                            theChanList <- readIORef chanListRef
                            addToClientRoomList clientNum (getChanRefByString chatroomName theChanList) clientListRef
                            theChanList <- readIORef chanListRef
                            hPutStrLn hdl $ printJoinedRoom chatroomName clientNum address theChanList
                            reader <- forkIO $ fix $ \loop -> do
                                (nextNum, line) <- readChan myChan
                                when (msgNum /= nextNum) $ hPutStrLn hdl line
                                loop
                            runConn (sock, address) hdl myChan msgNum clientNum clientListRef chanListRef
                Just x -> do
                            myChan <- dupChan x
                            hPutStrLn hdl $ printJoinedRoom chatroomName clientNum address theChanList
                            reader <- forkIO $ fix $ \loop -> do
                                (nextNum, line) <- readChan myChan
                                when (msgNum /= nextNum) $ hPutStrLn hdl line
                                loop
                            runConn (sock, address) hdl myChan msgNum clientNum clientListRef chanListRef
        5 -> do
              let roomRef = read (dropCommand $ getFirstLine message)::Int
              let joinId = read (dropCommand $ getLineX 2 message) ::Int
              theClientList <- readIORef clientListRef
              let clientName = unpackJustString $ getClientNameById joinId theClientList
              removeFromClientRoomList joinId roomRef clientListRef
              hPutStrLn hdl $ getLeftRoomMessage message
              writeChan chan (msgNum, (clientName ++ " has left the chatroom."))
              runConn (sock, address) hdl chan msgNum clientNum clientListRef chanListRef
        6 -> errorMessage hdl 1
      runConn (sock, address) hdl chan msgNum clientNum clientListRef chanListRef
      else errorMessage hdl 2

printJoinedRoom :: String -> Int -> SockAddr -> [(Int, String, Chan Msg)]  -> String
printJoinedRoom roomName clientNum address chanList = do
                                    let ip = getSockAddress address
                                    let port = getSockPort address
                                    let roomRef = show $ getChanRefByString roomName chanList
                                    let clientRef = show clientNum
                                    "JOINED_CHATROOM: " ++ roomName ++ "\nSERVER_IP:" ++ ip ++"\nPORT: "++ port ++ "\nROOM_REF: "++ roomRef ++ "\nJOIN_ID:" ++ clientRef

getLeftRoomMessage :: String -> String
getLeftRoomMessage msg  = do
                      let roomRef = dropCommand $ getFirstLine msg
                      let joinId = dropCommand $ head $ tail (lines msg)
                      "LEFT_CHATROOM: " ++ roomRef ++ "\nJOIN_ID:" ++ joinId


getClientName :: String -> String
getClientName x = tail $ reverse $ take (unpackJustInt(elemIndex ':' $ reverse x)) $ reverse x

getFirstLine :: String -> String
getFirstLine x = head $ lines x

getLineX :: Int -> String -> String
getLineX x y = (lines y) !! (x+1)

getCommand :: String -> String
getCommand x = take (unpackJustInt(elemIndex ':' $ x)) $ x

dropCommand :: String -> String
dropCommand x = drop ((unpackJustInt(elemIndex ':' x)) + 1) $ x

getChatroomName :: String -> String
getChatroomName x = tail $ reverse $ take (unpackJustInt(elemIndex ':' $ reverse (getFirstLine x))) $ reverse (getFirstLine x)

unpackJustChan :: Maybe (Chan Msg) -> Chan Msg
unpackJustChan (Just a) = a

unpackJustString :: Maybe String -> String
unpackJustString (Just a) = a

unpackJustInt :: Maybe Int -> Int
unpackJustInt (Just a) = a
unpackJustInt _  = 404

getSockPort :: SockAddr -> String
getSockPort x = tail $ drop (unpackJustInt(elemIndex ':' $ show x)) $ show x

getSockAddress :: SockAddr -> String
getSockAddress x = take (unpackJustInt(elemIndex ':' $ show x)) $ show x

sendHeloText :: SockAddr -> Handle -> IO()
sendHeloText address hdl = hPutStr hdl ("HELO text\nIP: "  ++ getSockAddress address ++ "\n" ++ "Port: " ++ getSockPort address ++ "\nStudentID: 13324607\n")

errorMessage :: Handle -> Int -> IO()
errorMessage hdl 1 = hPutStr hdl "ERROR CODE: 1\nERROR_DESCRIPTION: Invalid input"
errorMessage hdl 3 = hPutStr hdl "ERROR CODE: 3\nERROR_DESCRIPTION: No chatroom exists for specified ref."
errorMessage hdl 4 = hPutStr hdl "ERROR CODE: 4\nERROR_DESCRIPTION: You are not a member of specified chatroom."
errorMessage hdl x = hPutStr hdl "ERROR CODE: 1\nERROR_DESCRIPTION: Undefined error"
