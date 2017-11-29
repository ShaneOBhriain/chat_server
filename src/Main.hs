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

  mainLoop sock listeningChan 0 1 referenceList

type Msg = (Int, String)

-- client defined by int (join id - unique) and string (username)
type Client = (Int, String)
type Chatroom = (Int, String, Chan Msg, [Client])

mainLoop :: Socket -> Chan Msg -> Int -> Int -> IORef [Chatroom]-> IO ()
mainLoop sock chan msgNum clientNum chatroomListRef = do
  conn <- accept sock
  hdl <- setHandle conn
  -- line above waits until join then runs line below
  forkIO (runConn conn hdl msgNum clientNum chatroomListRef)
  mainLoop sock chan (msgNum+1) (clientNum + 1) chatroomListRef

addClient :: Client -> Chatroom -> IORef [Chatroom]-> IO ()
addClient client@(ref,name) room@(cRef,cName,chan,members) chatroomListRef = do
    if elem client members then putStrLn $ name ++ " is already a member of " ++ cName
    else do
      chatroomList <- readIORef chatroomListRef
      let newList = deleteN (unpackJustInt $ elemIndex room chatroomList) chatroomList
      let newRoom = (cRef,cName,chan, (client:members))
      writeIORef chatroomListRef (newRoom:newList)


deleteN :: Int -> [a] -> [a]
deleteN _ []     = []
deleteN i (a:as)
   | i == 0    = as
   | otherwise = a : deleteN (i-1) as

getClientRef :: (Int,String,[Int]) -> Int
getClientRef (a,b,c) = a

clientInRoom :: Client -> Chatroom -> Bool
clientInRoom client (a,b,c,d) = elem client d

-- addToClientRoomList :: Int -> Int -> IORef [(Int, String, [Int])] -> IO()
-- addToClientRoomList joinId roomId clientListRef = do
--   putStrLn "adding to client room list"
--   clientList <- readIORef clientListRef
--   let indexOfClientToEdit = unpackJustInt $ elemIndex joinId (map getClientRef clientList)
--   let (a,b,c) = clientList !! indexOfClientToEdit
--   let newClient = (a,b,roomId:c)
--   let newClientList = deleteN indexOfClientToEdit clientList
--   let finalClientList = newClient:newClientList
--   writeIORef clientListRef finalClientList

-- removeFromClientRoomList :: Int -> Int -> IORef [(Int, String, [Int])] -> IO()
-- removeFromClientRoomList joinId roomId clientListRef = do
--   putStrLn "removing from client room list"
--   clientList <- readIORef clientListRef
--   let indexOfClientToEdit = unpackJustInt $ elemIndex joinId (map getClientRef clientList)
--   let (a,b,c) = clientList !! indexOfClientToEdit
--   let newClientList = deleteN indexOfClientToEdit clientList
--
--   if elem roomId c then do
--     let newC = deleteN (unpackJustInt $ elemIndex roomId (map getClientRef clientList)) c
--     let newClient = (a,b,newC)
--     let finalClientList = newClient:newClientList
--     writeIORef clientListRef finalClientList
--   else putStrLn "Tried to leave chat but wasn't a member of the room."

-- getClientById :: Int -> [Client] -> Client
-- getClientById _ [] = (999,"Failed")
-- getClientById ref (client@(a,b):ys)
--               | ref == a = client
--               | otherwise = getClientById ref ys

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

addToChanList :: String -> Chan Msg -> IORef [Chatroom] -> IO ()
addToChanList newChanName myChan var = do
    val <- readIORef var
    let ref = length val + 1
    let newVal = (ref, newChanName,myChan, []):val
    writeIORef var newVal

getChatroomByString :: String -> [Chatroom] -> Maybe Chatroom
getChatroomByString name [] = Nothing
getChatroomByString name (room@(a,b,c,d):ys)
                  | name == b = Just $ room
                  | otherwise = getChatroomByString name ys

getChatroomByRef :: Int -> [Chatroom] -> Chatroom
getChatroomByRef ref (room@(a,b,c,d):ys)
                  | ref == a = room
                  | otherwise = getChatroomByRef ref ys

getChatroomChan :: Chatroom -> Chan Msg
getChatroomChan (_,_,c,_) = c

getChanRefByString :: String -> [Chatroom] -> Int
getChanRefByString name ((a,b,c,d):ys)
                  | name == b = a
                  | otherwise = getChanRefByString name ys

sendMessage :: String -> Int -> Chan Msg -> IO()
sendMessage bigMessage msgNum chan = writeChan chan (msgNum, unlines (head (myLines bigMessage) : tail (tail (myLines bigMessage))) )
-- sendMessage bigMessage msgNum chan = writeChan chan (msgNum, "unlines (head (myLines bigMessage) : tail (tail (myLines bigMessage)))" )

errorCheckMessage :: Integer -> [String] -> Bool
errorCheckMessage 2 l = [getCommand x | x <- l] == ["CHAT","JOIN_ID", "CLIENT_NAME","MESSAGE"]
errorCheckMessage 4 l = [getCommand x | x <- l] == ["JOIN_CHATROOM","CLIENT_IP", "PORT","CLIENT_NAME"]
errorCheckMessage _ _ = True

processMessage :: String -> IO Integer
processMessage msg
    | "KILL_SERVICE" == msg = return 0
    | "HELO_text" == msg = return 1
    | "CHAT" == msg = return 2
    | "DISCONNECT" == msg = return 3
    | "JOIN_CHATROOM" == msg = return 4
    | "LEAVE_CHATROOM" == msg = return 5
    | otherwise = return 6

replace :: Eq a => [a] -> [a] -> [a] -> [a]
replace needle replacement haystack
  = case begins haystack needle of
      Just remains -> replacement ++ remains
      Nothing      -> case haystack of
                        []     -> []
                        x : xs -> x : replace needle replacement xs

myLines:: String -> [String]
myLines = splitOn "|" . replaceAll

replaceAll:: String -> String
replaceAll = replace "\\n" "|" . replace "\\n" "|" . replace "\\n" "|"  . replace "\\n" "|" .replace "\\n\\n" ""

begins :: Eq a => [a] -> [a] -> Maybe [a]
begins haystack []                = Just haystack
begins (x : xs) (y : ys) | x == y = begins xs ys
begins _        _                 = Nothing

trim :: String -> String
trim = f . f
   where f = reverse . dropWhile (==' ')

runConn :: (Socket, SockAddr) -> Handle -> Int -> Int -> IORef [Chatroom] -> IO()
runConn (sock, address) hdl msgNum clientNum chatroomListRef = do
  message <- fmap init (hGetLine hdl)
  messageType <- processMessage $ getCommand (getFirstLine message)
  print message
  print $ show messageType
  print $ replaceAll message
  print $ myLines message
  case messageType of
    0 -> hClose hdl
    1 -> sendHeloText address hdl
    2 -> do
          putStrLn "about to send message"
          theChatroomList <- readIORef chatroomListRef
          let roomRef = read (dropCommand $ getFirstLine message)::Int
          let receivingChatroom@(a,b,c,d) = getChatroomByRef roomRef theChatroomList
          let client@(a,b) = (clientNum, (dropCommand $ getLineX 3 message))
          putStrLn $ "Checking " ++ (show d) ++ " for " ++ (show client)
          if clientInRoom client receivingChatroom then sendMessage message msgNum (getChatroomChan receivingChatroom)
          else errorMessage hdl 4
    3 -> do
          putStrLn "Disconnecting"
          hClose hdl
    4 -> do
          putStrLn "Joining chatroom"
          let clientName = dropCommand $ getLineX 4 message
          putStrLn $ "Got client name: " ++ clientName
          let chatroomName = dropCommand (getFirstLine message)
          putStrLn $ "Got chatroomName name: " ++ chatroomName

          theChatroomList <- readIORef chatroomListRef

          let myNewChan = getChatroomByString chatroomName theChatroomList

          case myNewChan of
            Nothing -> do
              myNewChan <- newChan
              addToChanList chatroomName myNewChan chatroomListRef
              theChatroomList <- readIORef chatroomListRef
              addClient (clientNum,clientName) (unpackJustChatroom $ getChatroomByString chatroomName theChatroomList) chatroomListRef
              putStrLn "Successfully created and joined chatroom."
              theChatroomList <- readIORef chatroomListRef
              hPutStrLn hdl $ printJoinedRoom chatroomName clientNum address theChatroomList
              reader <- forkIO $ fix $ \loop -> do
                (nextNum, line) <- readChan myNewChan
                when (msgNum /= nextNum) $ hPutStrLn hdl line
                loop
              runConn (sock, address) hdl msgNum clientNum chatroomListRef
            Just existingChatroom@(ref,name,chatroomChan,clientList)-> do
              myChan <- dupChan chatroomChan
              addClient (clientNum,clientName) existingChatroom chatroomListRef
              putStrLn $ "Chatroom [" ++ chatroomName ++ "] already exists."
              hPutStrLn hdl $ printJoinedRoom chatroomName clientNum address theChatroomList
              reader <- forkIO $ fix $ \loop -> do
                (nextNum, line) <- readChan myChan
                when (msgNum /= nextNum) $ hPutStrLn hdl line
                loop
              runConn (sock, address) hdl msgNum clientNum chatroomListRef

          -- case myNewChan of
          --   Nothing -> do
          --               myChan <- newChan
          --               addToChanList chatroomName myChan chatroomListRef
          --               theChatroomList <- readIORef chatroomListRef
          --               addToClientRoomList clientNum (getChanRefByString chatroomName theChatroomList) clientListRef
          --               theChatroomList <- readIORef chatroomListRef
          --               hPutStrLn hdl $ printJoinedRoom chatroomName clientNum address theChatroomList
          --               reader <- forkIO $ fix $ \loop -> do
          --                   (nextNum, line) <- readChan myChan
          --                   when (msgNum /= nextNum) $ hPutStrLn hdl line
          --                   loop
          --               runConn (sock, address) hdl myChan msgNum clientNum clientListRef chatroomListRef
          --   Just x -> do
          --               myChan <- dupChan x
          --               addToClientRoomList clientNum (getChanRefByString chatroomName theChatroomList) clientListRef
          --               hPutStrLn hdl $ printJoinedRoom chatroomName clientNum address theChatroomList
          --               reader <- forkIO $ fix $ \loop -> do
          --                   (nextNum, line) <- readChan myChan
          --                   when (msgNum /= nextNum) $ hPutStrLn hdl line
          --                   loop
          --               runConn (sock, address) hdl myChan msgNum clientNum clientListRef chatroomListRef
    5 -> do
          putStrLn "leaving chatroom"
          -- TODO: fix
          let roomRef = read (dropCommand $ getFirstLine message)::Int
          let joinId = read (dropCommand $ getLineX 2 message) ::Int
          let theClientList = []
          let clientName = unpackJustString $ getClientNameById joinId theClientList
          -- removeFromClientRoomList joinId roomRef clientListRef
          hPutStrLn hdl $ getLeftRoomMessage message
          -- writeChan chan (msgNum, (clientName ++ " has left the chatroom."))
          runConn (sock, address) hdl msgNum clientNum chatroomListRef
    6 -> errorMessage hdl 1
  runConn (sock, address) hdl msgNum clientNum chatroomListRef

printJoinedRoom :: String -> Int -> SockAddr -> [Chatroom]  -> String
printJoinedRoom roomName clientNum address chanList = do
                                    let ip = getSockAddress address
                                    let port = getSockPort address
                                    let roomRef = show $ getChanRefByString roomName chanList
                                    let clientRef = show clientNum
                                    "JOINED_CHATROOM: " ++ roomName ++ "\nSERVER_IP:" ++ ip ++"\nPORT: "++ port ++ "\nROOM_REF: "++ roomRef ++ "\nJOIN_ID:" ++ clientRef

getLeftRoomMessage :: String -> String
getLeftRoomMessage msg  = do
                      let roomRef = dropCommand $ getFirstLine msg
                      let joinId = dropCommand $ head $ tail (myLines msg)
                      "LEFT_CHATROOM: " ++ roomRef ++ "\nJOIN_ID:" ++ joinId


getClientName :: String -> String
getClientName x = tail $ reverse $ take (unpackJustInt(elemIndex ':' $ reverse x)) $ reverse x

getFirstLine :: String -> String
getFirstLine x = head $ myLines x

getLineX :: Int -> String -> String
getLineX x y = (myLines y) !! (x-1)

getCommand :: String -> String
getCommand x = trim $ take (unpackJustInt(elemIndex ':' $ x)) $ x

dropCommand :: String -> String
dropCommand x = trim $ drop ((unpackJustInt(elemIndex ':' x)) + 1) $ x

getChatroomName :: String -> String
getChatroomName x = tail $ reverse $ take (unpackJustInt(elemIndex ':' $ reverse (getFirstLine x))) $ reverse (getFirstLine x)

unpackJustChatroom :: Maybe Chatroom -> Chatroom
unpackJustChatroom (Just a) = a

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
errorMessage hdl 1 = hPutStrLn hdl "ERROR CODE: 1\nERROR_DESCRIPTION: Invalid input"
errorMessage hdl 3 = hPutStrLn hdl "ERROR CODE: 3\nERROR_DESCRIPTION: No chatroom exists for specified ref."
errorMessage hdl 4 = hPutStrLn hdl "ERROR CODE: 4\nERROR_DESCRIPTION: You are not a member of specified chatroom."
errorMessage hdl x = hPutStrLn hdl "ERROR CODE: 1\nERROR_DESCRIPTION: Undefined error"
