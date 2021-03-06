{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable, DeriveDataTypeable #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Call.Types
-- Copyright   :  (c) Fumiaki Kinoshita 2014
-- License     :  BSD3
--
-- Maintainer  :  Fumiaki Kinoshita <fumiexcel@gmail.com>
-- Stability   :  experimental
-- Portability :  non-portable
--
-----------------------------------------------------------------------------
module Call.Types (
    Time
    , Vec2
    , Vec3
    , Stereo
    , WindowMode(..)
    , MouseEvent(..)
    , Gamepad(..)
    , GamepadEvent(..)
    , Chatter(..)
    , Key(..)
    , charToKey
    , BlendMode(..)
    , Vertex(..)
    , positionUV
    , positionOnly
    , Bitmap(..)
    ) where

import Control.Applicative
import Linear
import Data.Typeable
import Data.Char
import Foreign.Storable
import Foreign.Ptr
import Call.Data.Bitmap

type Time = Float
type Stereo = V2 Float
type Vec2 = V2 Float
type Vec3 = V3 Float
data WindowMode = Windowed | Resizable | FullScreen deriving (Show, Eq, Ord, Read, Typeable)

data Chatter a = Up a | Down a deriving (Show, Eq, Ord, Read, Typeable)

data MouseEvent = Button (Chatter Int) | Cursor Vec2 | Scroll Vec2 deriving (Show, Eq, Ord, Read, Typeable)

data Gamepad = Gamepad Int String deriving (Show, Eq, Ord, Read, Typeable)

data GamepadEvent = PadButton Gamepad (Chatter Int) | PadConnection (Chatter Gamepad) deriving (Show, Eq, Ord, Read, Typeable)

data Key =
      KeyUnknown
    | KeySpace
    | KeyApostrophe
    | KeyComma
    | KeyMinus
    | KeyPeriod
    | KeySlash
    | Key0
    | Key1
    | Key2
    | Key3
    | Key4
    | Key5
    | Key6
    | Key7
    | Key8
    | Key9
    | KeySemicolon
    | KeyEqual
    | KeyA
    | KeyB
    | KeyC
    | KeyD
    | KeyE
    | KeyF
    | KeyG
    | KeyH
    | KeyI
    | KeyJ
    | KeyK
    | KeyL
    | KeyM
    | KeyN
    | KeyO
    | KeyP
    | KeyQ
    | KeyR
    | KeyS
    | KeyT
    | KeyU
    | KeyV
    | KeyW
    | KeyX
    | KeyY
    | KeyZ
    | KeyLeftBracket
    | KeyBackslash
    | KeyRightBracket
    | KeyGraveAccent
    | KeyWorld1
    | KeyWorld2
    | KeyEscape
    | KeyEnter
    | KeyTab
    | KeyBackspace
    | KeyInsert
    | KeyDelete
    | KeyRight
    | KeyLeft
    | KeyDown
    | KeyUp
    | KeyPageUp
    | KeyPageDown
    | KeyHome
    | KeyEnd
    | KeyCapsLock
    | KeyScrollLock
    | KeyNumLock
    | KeyPrintScreen
    | KeyPause
    | KeyF1
    | KeyF2
    | KeyF3
    | KeyF4
    | KeyF5
    | KeyF6
    | KeyF7
    | KeyF8
    | KeyF9
    | KeyF10
    | KeyF11
    | KeyF12
    | KeyF13
    | KeyF14
    | KeyF15
    | KeyF16
    | KeyF17
    | KeyF18
    | KeyF19
    | KeyF20
    | KeyF21
    | KeyF22
    | KeyF23
    | KeyF24
    | KeyF25
    | KeyPad0
    | KeyPad1
    | KeyPad2
    | KeyPad3
    | KeyPad4
    | KeyPad5
    | KeyPad6
    | KeyPad7
    | KeyPad8
    | KeyPad9
    | KeyPadDecimal
    | KeyPadDivide
    | KeyPadMultiply
    | KeyPadSubtract
    | KeyPadAdd
    | KeyPadEnter
    | KeyPadEqual
    | KeyLeftShift
    | KeyLeftControl
    | KeyLeftAlt
    | KeyLeftSuper
    | KeyRightShift
    | KeyRightControl
    | KeyRightAlt
    | KeyRightSuper
    | KeyMenu
    deriving (Enum, Eq, Ord, Read, Show, Typeable, Bounded)

charToKey :: Char -> Key
charToKey ch
    | isAlpha ch = toEnum $ fromEnum KeyA + fromEnum ch - fromEnum 'A'
    | isDigit ch = toEnum $ fromEnum Key0 + fromEnum ch - fromEnum '0'
charToKey '-' = KeyMinus
charToKey ',' = KeyComma
charToKey '.' = KeyPeriod
charToKey '/' = KeySlash
charToKey ' ' = KeySpace
charToKey '\'' = KeyApostrophe
charToKey '\\' = KeyBackslash
charToKey '=' = KeyEqual
charToKey ';' = KeySemicolon
charToKey '[' = KeyLeftBracket
charToKey ']' = KeyRightBracket
charToKey '`' = KeyGraveAccent
charToKey '\n' = KeyEnter
charToKey '\r' = KeyEnter
charToKey '\t' = KeyTab
charToKey _ = KeyUnknown

data BlendMode = Normal
    | Inverse
    | Add
    | Multiply
    | Screen
    deriving (Enum, Eq, Ord, Read, Show, Typeable)

data Vertex = Vertex { vPos :: {-# UNPACK #-} !Vec3
  , vUV :: {-# UNPACK #-} !Vec2
  , vNormal :: {-# UNPACK #-} !Vec3 }
  deriving (Show, Eq, Ord, Read, Typeable)

align1 :: Int
align1 = sizeOf (vPos undefined)

align2 :: Int
align2 = align1 + sizeOf (vUV undefined)

instance Storable Vertex where
  sizeOf _ = sizeOf (undefined :: Vec3) + sizeOf (undefined :: Vec2) + sizeOf (undefined :: Vec3)
  alignment _ = 0
  peek ptr = Vertex
    <$> peek (castPtr ptr)
    <*> peek (castPtr $ ptr `plusPtr` align1)
    <*> peek (castPtr $ ptr `plusPtr` align2)
  poke ptr (Vertex v t n) = do
    poke (castPtr ptr) v
    poke (castPtr ptr `plusPtr` align1) t
    poke (castPtr ptr `plusPtr` align2) n

positionUV :: Vec3 -> Vec2 -> Vertex
positionUV v p = Vertex v p zero

positionOnly :: Vec3 -> Vertex
positionOnly v = Vertex v zero zero