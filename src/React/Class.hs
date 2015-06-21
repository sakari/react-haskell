{-# LANGUAGE NamedFieldPuns, OverloadedStrings, DataKinds,
    ExistentialQuantification #-}
module React.Class
    ( ReactClass(..)
    , ClassConfig(..)
    , createClass
    , smartClass
    , dumbClass
    ) where


import Control.Monad
import qualified Data.HashMap.Strict as H
import Data.IORef
import System.IO.Unsafe

import GHCJS.Foreign
import GHCJS.Marshal
import GHCJS.Types

import React.Imports
import React.Types


data ClassConfig props state insig exsig = ClassConfig
    { renderFn :: props -> state -> ReactNode insig
    , getInitialState :: state
    , name :: JSString
    , transition :: (state, insig) -> (state, Maybe exsig)
    , startupSignals :: [insig]
    }


dumbClass :: ClassConfig props () sig sig
dumbClass = ClassConfig
    { name = "Anonymous Stateless Class"
    , renderFn = \_ _ -> "give this class a `render`!"
    , getInitialState = ()
    , transition = \(state, sig) -> (state, Just sig)
    , startupSignals = []
    }


smartClass :: ClassConfig props state insig exsig
smartClass = ClassConfig
    { name = "Anonymous Stateful Class"
    , renderFn = \_ _ -> "give this class a `render`!"
    , getInitialState = error "must define `getInitialState`!"
    , transition = error "must define `transition`!"
    , startupSignals = []
    }


willMount :: ClassRegistry props state -> state -> JSRef Int -> IO ()
willMount registry state idRef = do
    -- initialize state in registry
    Just componentId <- fromJSRef idRef
    setState registry state componentId


willUnmount :: ClassRegistry props state -> JSRef Int -> IO ()
willUnmount registry idRef = do
    -- remove state from registry
    Just componentId <- fromJSRef idRef
    deallocRegistry registry componentId


-- TODO(joel) why not just pass in the class config?
render :: ClassRegistry props state
       -> (props -> state -> ReactNode insig)
       -> JSRef Int
       -> JSAny
       -> IO ()
render registry renderFn idRef returnObj = do
    -- **
    -- The fundamental tension here is that this render function is
    -- defined for the class, but each invocation needs access to a
    -- specific instance. How do we get a handle to that specific
    -- instance? This will give us the props and state (and
    -- handler?)
    --
    -- We can't just invent a `js_this` function because that just
    -- gives us a `JSAny`. How do we leverage that to extract the
    -- IORef?
    --
    -- handler may be interesting here.

    Just componentId <- fromJSRef idRef
    (thisProps, thisState) <- lookupRegistry registry componentId

    let rendered = renderFn thisProps thisState
        -- * use transition
        --   transition :: (state, insig) -> (state, exsig)
        -- * update IORef or something

        -- rendered :: ReactComponentElement sig
        -- *holds state stuff*

        -- handler :: insig -> IO ()
        handler sig = putStrLn "TODO(joel) in handler!"
    ret <- reactNodeToJSAny handler componentId rendered
    setProp ("value" :: JSString) ret returnObj


createClass :: ClassConfig props state insig exsig
            -> ReactClass props state insig exsig
createClass ClassConfig{renderFn,
                        getInitialState,
                        name,
                        transition,
                        startupSignals} =

    -- TODO(joel) - verify this use of unsafePerformIO is, well, safe
    let classRegistry = unsafePerformIO $ ClassRegistry
            <$> newIORef H.empty
            <*> newIORef H.empty
            <*> newIORef 0

        foreignObj = do
            obj <- newObj

            setProp ("displayName" :: JSString) name obj

            renderCb <- syncCallback2 NeverRetain True
                (render classRegistry renderFn)
            setProp ("render" :: JSString) renderCb obj

            willMountCb <- syncCallback1 NeverRetain True
                (willMount classRegistry getInitialState)
            setProp ("componentWillMount" :: JSString) willMountCb obj

            willUnmountCb <- syncCallback1 NeverRetain True
                (willUnmount classRegistry)
            setProp ("componentWillUnmount" :: JSString) willUnmountCb obj

            return obj
        foreignClass = js_createClass <$> foreignObj

    in ReactClass foreignClass renderFn getInitialState name transition classRegistry
