-- "THE BEER-WARE LICENSE" (Revision 42):
-- Albatrouss and <skruppy@onmars.eu> wrote this software. As long as you retain
-- this notice you can do whatever you want with this stuff. If we meet some
-- day, and you think this stuff is worth it, you can buy me a beer in return.
--                                                     -- Albatrouss and Skruppy

module Main where

import AI as AI
import Conf as C
import Conf.Args as CA
import Conf.Gui as CG
import Control.Concurrent
import Control.Concurrent.MVar
import Data.String.Utils
import Data.Version (showVersion)
import GameGUI as GG
import Graphics.UI.Gtk
import Graphics.UI.Gtk.Windows.MessageDialog
import Net
import Network.Socket as NS
import PP as PP
import Paths_funthello (version)
import Sm as S
import System.Console.ANSI
import System.Environment
import System.Exit
import System.IO
import Util


-- The name speaks for it self. Here you are looking at the beautiful main-l↺↺p.
(↺) :: Handle -> StepResult -> IO (Either String (GameData, Maybe Int, Board))
(↺) hdl (SmEnd gameData winner board) = return $ Right (gameData, winner, board)
(↺) hdl (SmError msg)                 = return $ Left msg
(↺) hdl (SmOk s o)                    = do
    i <- converse hdl o
    let (s', io) = smStep s i
    io
    (↺) hdl s'


play gameId' player' ai socket = do
    -- Convert socket to unbuffered handle
    hdl <- socketToHandle socket ReadWriteMode
    hSetBuffering hdl NoBuffering
    
    -- Main loop
    res <- (↺) hdl $ smCreate S.Cfg {
          S.gameId = gameId'
        , S.player = player'
        , S.ai     = ai
        }
    
    -- So close!
    hClose hdl
    return res


finalizeCfg :: IntermediateCfg -> IO (Either String (String, Maybe Int, NS.Socket))
finalizeCfg IntermediateCfg { C.host   = Nothing } = return $ Left "Missing hostname"
finalizeCfg IntermediateCfg { C.port   = Nothing } = return $ Left "Missing port"
finalizeCfg IntermediateCfg { C.gameId = Nothing } = return $ Left "Missing game ID"
finalizeCfg IntermediateCfg
    { C.host   = Just host'
    , C.port   = Just port'
    , C.gameId = Just gameId'
    , C.player =      player'
    }
    = do
    res <- Net.connect host' port'
    case res of
        Right socket -> return $ Right (gameId', player', socket)
        Left msg     -> return $ Left msg


getGuiCfg :: Gui -> String -> IO (String, Maybe Int, NS.Socket)
getGuiCfg gui msg = do
    -- Get config from GUI
    cfg <- CG.getCfg gui msg
    
    -- Try to make final config
    res <- finalizeCfg cfg
    case res of
        Right finalCfg -> return finalCfg
        Left  msg      -> getGuiCfg gui msg


guiMode cfg = do
    gui <- CG.createGui cfg
    (gameId', player', socket) <- getGuiCfg gui ""

    mVarField <- newEmptyMVar
    mVarGameData <- newEmptyMVar
    forkIO $ GG.createGameGUI mVarField mVarGameData
    
    let ai = \gameData field time -> (
            AI.getNextMove field gameData
          , do
              tryPutMVar mVarField field
              tryPutMVar mVarGameData gameData
              PP.prettyPrint field
          )
    
    res <- play gameId' player' ai socket
    case res of
        Right (gameData, winner, board) -> do
            tryPutMVar mVarField board
            tryPutMVar mVarGameData gameData
            PP.prettyPrint board
            
            window <- messageDialogNew
                Nothing
                []
                MessageError
                ButtonsOk
                "Game over"
            
            dialogRun window
            widgetDestroy window
            
            return True
        
        Left msg -> do
            window <- messageDialogNew
                Nothing
                []
                MessageError
                ButtonsOk
                msg
            
            dialogRun window
            widgetDestroy window
            
            return False


consoleMode cfg = do
    res <- finalizeCfg cfg
    case res of
        Right (gameId', player', socket) -> do
            let ai = \gameData field time -> ((AI.getNextMove field gameData) , PP.prettyPrint field)
            res <- play gameId' player' ai socket
            case res of
                Right _ -> return True
                Left _ -> return False
        
        -- Configuration error
        Left msg -> do
            putStrLn msg
            return False


main :: IO ()
main = do
    -- Config from command line
    argsCfg <- CA.getCfg
    
    -- http://patorjk.com/software/taag/#p=display&f=Big&t=funthello
    setSGR [SetConsoleIntensity BoldIntensity]
    putStrLn "   ______           _   _          _ _"
    putStrLn "   |  ___|         | | | |        | | |"
    putStrLn "   | |_ _   _ _ __ | |_| |__   ___| | | ___"
    putStrLn "   |  _| | | | '_ \\| __| '_ \\ / _ \\ | |/ _ \\"
    putStrLn "   | | | |_| | | | | |_| | | |  __/ | | (_) |"
    putStrLn "   \\_|  \\__,_|_| |_|\\__|_| |_|\\___|_|_|\\___/"
    setSGR [Reset]
    putStrLn ""
    setSGR [SetColor Foreground Dull Green]
    putStr   "   Loading version "
    putStr   $ showVersion version
    putStr   " "
    setSGR [SetBlinkSpeed SlowBlink]
    putStr   "_"
    putStrLn ""
    setSGR [Reset]
    putStrLn ""

    let cfg = mergeCfg [argsCfg, defaultCfg]
    progName <- getProgName
    
    ret <- if endswith "-gui" progName
    then guiMode cfg
    else consoleMode cfg
    
    if ret
    then exitSuccess
    else exitFailure
