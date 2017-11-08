-- Main.hs, final code
module Main where

import Network.Socket
import System.IO
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
  chan <- newChan
  _ <- forkIO $ fix $ \loop -> do
    (_, _) <- readChan chan
    loop
  mainLoop sock chan 0

data Message  = In MessageType
							| Out MessageType

data MessageType name pattern = definition
type Msg = (Int, String)

mainLoop :: Socket -> Chan Msg -> Int -> IO ()
mainLoop sock chan msgNum = do
  conn <- accept sock
  forkIO (runConn conn chan msgNum)
  -- $! = strict function application
  mainLoop sock chan $! msgNum + 1


-- getSockPort :: Socket -> String
-- getSockPort x = do:

-- getHeloText :: SockAddr -> String
-- getHeloText (port,address) = "HELO text\nIP: " ++ show address ++ "\n" ++ "Port: " ++ show port ++ "\nStudentID: 13324607\n"

runConn :: (Socket, SockAddr) -> Chan Msg -> Int -> IO ()
runConn (sock, address) chan msgNum = do
    let broadcast msg = writeChan chan (msgNum, msg)
    hdl <- socketToHandle sock ReadWriteMode
    hSetBuffering hdl NoBuffering

    hPutStrLn hdl "Hi, what's your name?"
    name <- fmap init (hGetLine hdl)
    broadcast ("--> " ++ name ++ " entered chat.")
    hPutStrLn hdl ("Welcome, " ++ name ++ "!")



    -- Duplicate a Chan: the duplicate channel begins empty, but data written to either channel from then on will be available from both.
    -- Hence this creates a kind of broadcast channel, where data written by anyone is seen by everyone else.
    commLine <- dupChan chan

    -- fork off a thread for reading from the duplicated channel
    reader <- forkIO $ fix $ \loop -> do
      -- Read the next value from the Chan. Blocks when the channel is empty.
      -- Since the read end of a channel is an MVar, this operation inherits fairness guarantees of MVars (e.g. threads blocked in this operation are woken up in FIFO order).
        (nextNum, line) <- readChan commLine
        when (msgNum /= nextNum) $ hPutStrLn hdl line
        loop

    handle (\(SomeException _) -> return ()) $ fix $ \loop -> do
        line <- fmap init (hGetLine hdl)
        case line of
              -- "KILL_SERVICE" -> hPutStrLn hdl "Bye!"
             -- If an exception is caught, send a message and break the loop
             "KILL_SERVICE" -> hPutStrLn hdl "Bye!"
             "HELO text" -> hPutStrLn hdl "Hello"
             -- else, continue looping.
             _      -> broadcast (name ++ ": " ++ line) >> loop

    killThread reader                      -- kill after the loop ends
    broadcast ("<-- " ++ name ++ " left.") -- make a final broadcast
    hClose hdl                  -- close handle
