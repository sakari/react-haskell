
-- Module      :  React
-- Copyright   :  (C) 2014-15 Joel Burget
-- License     :  MIT
-- Maintainer  :  Joel Burget <joelburget@gmail.com>
-- Stability   :  experimental
-- Portability :  non-portable
module React
    ( module X

    -- React.Class
    , ReactClass()
    , ClassConfig(..)
    , createClass
    , smartClass
    , dumbClass

    -- React.Render
    , render
    , debugRender

    -- React.Types
    , RenderHandle(..)
    , EventProperties(..)
    , Target(..)
    , ModifierKeys(..)
    , MouseEvent(..)
    , KeyboardEvent(..)
    , ChangeEvent(..)
    , FocusEvent(..)
    , ForeignRender

    , ReactType(..)
    , ReactNode

    -- XXX(joel)
    , AttrOrHandler()
    , RawAttrs(..)
    , ReactArray(..)
    , ForeignNode(..)
    , mkStaticAttr
    ) where

-- TODO
-- restricted monads
-- store elem in monad
-- escaping / dangerouslySetInnerHTML

import React.Class
-- import React.Local
import React.Render
import React.Types

import React.Attrs as X
import React.Elements as X
import React.Events as X
import React.Rebindable as X
