{-# LANGUAGE OverloadedStrings #-}
module React.Interpret (reactNodeToJSAny) where

import Control.Monad
import qualified Data.Aeson as Aeson
import qualified Data.HashMap.Strict as H
import Data.List
import Data.Maybe
import Data.Text (Text)

import React.Imports
import React.Registry
import React.Types


data Attr = Attr Text JSON


jsName :: EvtType -> JSString
jsName ChangeEvt = "onChange"
jsName KeyDownEvt = "onKeyDown"
jsName KeyPressEvt = "onKeyPress"
jsName KeyUpEvt = "onKeyUp"
jsName ClickEvt = "onClick"
jsName DoubleClickEvt = "onDoubleClick"
jsName MouseEnterEvt = "onMouseEnter"
jsName MouseLeaveEvt = "onMouseLeave"


unHandler :: (s -> IO ())
          -> EventHandler s
          -> (Int -> RawEvent -> Maybe (IO ()), EvtType)
unHandler act (EventHandler handle ty) = (\ix e -> act <$> handle ix e, ty)


makeHandler :: Int
            -- ^ component id
            -> JSAny
            -- ^ object to set this attribute on
            -> (Int -> RawEvent -> Maybe (IO ()), EvtType)
            -- ^ handler
            -> IO ()
makeHandler componentId obj (handle, evtTy) = do
    handle' <- handlerToJs handle
    js_set_handler componentId (jsName evtTy) handle' obj


-- | Make a javascript callback to synchronously execute the handler
handlerToJs :: (Int -> RawEvent -> Maybe (IO ()))
            -> IO (JSFun (JSRef Int -> RawEvent -> IO ()))
handlerToJs handle = syncCallback2 AlwaysRetain True $ \idRef evt -> do
    Just componentId <- fromJSRef idRef
    fromMaybe (return ()) (handle componentId evt)


attrsToJson :: [Attr] -> JSON
attrsToJson = Aeson.toJSON . H.fromList . map unAttr where
    unAttr (Attr name json) = (name, json)


separateAttrs :: [AttrOrHandler sig] -> ([Attr], [EventHandler sig])
separateAttrs attrHandlers = (map makeA as, map makeH hs) where
    (as, hs) = partition isAttr attrHandlers

    isAttr :: AttrOrHandler sig -> Bool
    isAttr (StaticAttr _ _) = True
    isAttr _ = False

    makeA :: AttrOrHandler sig -> Attr
    makeA (StaticAttr t j) = Attr t j

    makeH :: AttrOrHandler sig -> EventHandler sig
    makeH (Handler h) = h


attrHandlerToJSAny :: (sig -> IO ()) -> Int -> [AttrOrHandler sig] -> IO JSAny
attrHandlerToJSAny sigHandler componentId attrHandlers = do
    let (attrs, handlers) = separateAttrs attrHandlers
    starter <- castRef <$> toJSRef (attrsToJson attrs)

    forM_ handlers $ makeHandler componentId starter . unHandler sigHandler
    return starter


reactNodeToJSAny :: (sig -> IO ()) -> Int -> ReactNode sig -> IO JSAny
reactNodeToJSAny sigHandler componentId (ComponentElement elem) =
    componentToJSAny sigHandler elem
reactNodeToJSAny sigHandler componentId (DomElement elem)       =
    domToJSAny sigHandler componentId elem
reactNodeToJSAny sigHandler _           (NodeText str)          =
    castRef <$> toJSRef str
reactNodeToJSAny sigHandler componentId (NodeSequence seq)      = do
    jsNodes <- mapM (reactNodeToJSAny sigHandler componentId) seq
    castRef <$> toArray jsNodes


-- Helper for componentToJSAny and domToJSAny
setMaybeKey :: Maybe JSString -> JSAny -> IO ()
setMaybeKey maybeKey attrsObj = when (isJust maybeKey) $ do
    let Just key = maybeKey
    setProp' "key" key attrsObj


setProp' :: ToJSRef a => String -> a -> JSAny -> IO ()
setProp' key prop obj = do
    propRef <- toJSRef prop
    setProp key propRef obj


componentToJSAny :: (sig -> IO ()) -> ReactComponentElement sig -> IO JSAny
componentToJSAny
    sigHandler
    (ReactComponentElement ty attrs children maybeKey ref props) = do

        let registry = classStateRegistry ty
        componentId <- allocProps registry props

        -- handle internal signals, maybe call external signal handler

        -- Register a handler! This transitions the class to its new state and
        -- outputs a signal if appropriate.
        let sigHandler' insig = do
                RegistryStuff _ state _ <-
                    lookupRegistry registry componentId
                let (state', maybeExSig) = classTransition ty (state, insig)
                setState registry state' componentId

                case maybeExSig of
                    Just exSig -> sigHandler exSig
                    Nothing -> return ()

        setHandler registry sigHandler' componentId

        attrsObj <- attrHandlerToJSAny sigHandler' componentId attrs

        setMaybeKey maybeKey attrsObj
        setProp' "ref" ref attrsObj
        setProp' "componentId" componentId attrsObj

        let ty' = classForeign ty
        children' <- reactNodeToJSAny sigHandler' componentId children

        castRef <$> js_react_createElement_Class ty' attrsObj children'


domToJSAny :: (sig -> IO ()) -> Int -> ReactDOMElement sig -> IO JSAny
domToJSAny sigHandler componentId (ReactDOMElement ty props children maybeKey ref) = do
    attrsObj <- attrHandlerToJSAny sigHandler componentId props

    setMaybeKey maybeKey attrsObj
    setProp' "ref" ref attrsObj

    children' <- reactNodeToJSAny sigHandler componentId children

    castRef <$> js_react_createElement_DOM ty attrsObj children'
