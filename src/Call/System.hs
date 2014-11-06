{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Call.System
-- Copyright   :  (c) Fumiaki Kinoshita 2014
-- License     :  BSD3
--
-- Maintainer  :  Fumiaki Kinoshita <fumiexcel@gmail.com>
-- Stability   :  experimental
-- Portability :  non-portable
--
-----------------------------------------------------------------------------
module Call.System (
  -- * The system
  System
  , runSystem
  , forkSystem
  , ObjS
  , AddrS
  -- * Wait
  , stand
  , wait
  -- * Raw input
  , keyPress
  , mousePosition
  , mouseButton
  -- * Component
  , newGraphic
  , newAudio
  , newKeyboard
  , newMouse
  , linkGraphic
  , linkAudio
  , linkKeyboard
  , linkMouse
  , unlinkGraphic
  , unlinkAudio
  , unlinkKeyboard
  , unlinkMouse) where

import Data.Color
import Call.Data.Bitmap
import Call.Sight
import Call.Types
import Call.Event
import Control.Applicative
import Control.Concurrent
import Control.Exception
import Control.Monad.IO.Class
import Control.Monad.Reader
import Control.Object
import Control.Monad.Objective
import Data.IORef
import Data.Reflection
import Linear
import qualified Call.Internal.GLFW as G
import qualified Data.IntMap.Strict as IM
import qualified Graphics.UI.GLFW as GLFW
import qualified Call.Internal.PortAudio as PA
import Graphics.Rendering.OpenGL.GL.StateVar
import qualified Graphics.Rendering.OpenGL.Raw as GL
import qualified Graphics.Rendering.OpenGL.GL as GL
import Unsafe.Coerce
import Foreign (castPtr, sizeOf, with)
import qualified Data.Vector.Storable as V
import Data.BoundingBox (Box(..))

type ObjS e s = Object e (System s)
type AddrS e s = Address e (System s)

newGraphic :: (Lift Graphic e) => ObjS e s -> System s (AddrS e s)
newGraphic o = new o >>= \a -> linkGraphic a >> return a

newAudio :: (Lift Audio e) => ObjS e s -> System s (AddrS e s)
newAudio o = new o >>= \a -> linkAudio a >> return a

newKeyboard :: (Lift Keyboard e) => ObjS e s -> System s (AddrS e s)
newKeyboard o = new o >>= \a -> linkKeyboard a >> return a

newMouse :: (Lift Mouse e) => ObjS e s -> System s (AddrS e s)
newMouse o = new o >>= \a -> linkMouse a >> return a

newtype System s a = System (ReaderT (Foundation s) IO a) deriving (Functor, Applicative, Monad)

unSystem :: Foundation s -> System s a -> IO a
unSystem f m = unsafeCoerce m f

mkSystem :: (Foundation s -> IO a) -> System s a
mkSystem = unsafeCoerce

forkSystem :: System s () -> System s ThreadId
forkSystem m = mkSystem $ \fo -> forkIO (unSystem fo m)

runSystem :: WindowMode -> BoundingBox2 -> (forall s. System s a) -> IO (Maybe a)
runSystem mode box m = do
  sys <- G.beginGLFW mode box
  f <- Foundation
    <$> newMVar 0
    <*> pure 44100 -- FIX THIS
    <*> newIORef IM.empty
    <*> newIORef IM.empty
    <*> newIORef IM.empty
    <*> newIORef IM.empty
    <*> newMVar 0
    <*> pure sys
    <*> newIORef 60
    <*> newIORef IM.empty
    <*> newEmptyMVar
  let win = G.theWindow sys
  GLFW.setKeyCallback win $ Just $ keyCallback f
  GLFW.setMouseButtonCallback win $ Just $ mouseButtonCallback f
  GLFW.setCursorPosCallback win $ Just $ cursorPosCallback f
  GLFW.setScrollCallback win $ Just $ scrollCallback f
  ref <- newEmptyMVar
  _ <- flip forkFinally (either throwIO (putMVar ref)) $ unSystem f m
  PA.with 44100 512 (audioProcess f) $ liftIO $ do
    GLFW.setTime 0
    runGraphic f 0
  G.endGLFW sys
  tryTakeMVar ref

linkMouse :: Lift Mouse e => AddrS e s -> System s ()
linkMouse (Control i mc) = mkSystem $ \fo -> modifyIORef (coreMouse fo) $ IM.insert i (Member lift_ mc)

linkKeyboard :: Lift Keyboard e => AddrS e s -> System s ()
linkKeyboard (Control i mc) = mkSystem $ \fo -> modifyIORef (coreKeyboard fo) $ IM.insert i (Member lift_ mc)

linkGraphic :: Lift Graphic e => AddrS e s -> System s ()
linkGraphic (Control i mc) = mkSystem $ \fo -> modifyIORef (coreGraphic fo) $ IM.insert i (Member lift_ mc)

linkAudio :: Lift Audio e => AddrS e s -> System s ()
linkAudio (Control i mc) = mkSystem $ \fo -> modifyIORef (coreAudio fo) $ IM.insert i (Member lift_ mc)

unlinkMouse :: AddrS e s -> System s ()
unlinkMouse (Control i _) = mkSystem $ \fo -> modifyIORef (coreMouse fo) $ IM.delete i

unlinkKeyboard :: AddrS e s -> System s ()
unlinkKeyboard (Control i _) = mkSystem $ \fo -> modifyIORef (coreKeyboard fo) $ IM.delete i

unlinkGraphic :: AddrS e s -> System s ()
unlinkGraphic (Control i _) = mkSystem $ \fo -> modifyIORef (coreGraphic fo) $ IM.delete i

unlinkAudio :: AddrS e s -> System s ()
unlinkAudio (Control i _) = mkSystem $ \fo -> modifyIORef (coreAudio fo) $ IM.delete i

stand :: System s ()
stand = mkSystem $ \fo -> takeMVar (theEnd fo)

wait :: Time -> System s ()
wait dt = mkSystem $ \fo -> do
  t0 <- takeMVar (theTime fo)
  Just t <- GLFW.getTime
  threadDelay $ floor $ (t0 - realToFrac t + dt) * 1000 * 1000
  putMVar (theTime fo) $ t0 + dt

keyPress :: Key -> System s Bool
keyPress k = mkSystem $ \fo -> fmap (/=GLFW.KeyState'Released)
  $ GLFW.getKey (G.theWindow $ theSystem fo) (toEnum . fromEnum $ k)

mousePosition :: System s (V2 Float)
mousePosition = mkSystem $ \fo -> do
  (x, y) <- GLFW.getCursorPos (G.theWindow $ theSystem fo)
  return $ V2 (realToFrac x) (realToFrac y)

mouseButton :: Int -> System s Bool
mouseButton b = mkSystem $ \fo -> fmap (/=GLFW.MouseButtonState'Released)
  $ GLFW.getMouseButton (G.theWindow $ theSystem fo) (toEnum b)

data Member e s where
  Member :: (forall x. e x -> f x) -> MVar (Object f (System s)) -> Member e s

data Foundation s = Foundation
  { newObjectId :: MVar Int
  , sampleRate :: Float
  , coreGraphic :: IORef (IM.IntMap (Member Graphic s))
  , coreAudio :: IORef (IM.IntMap (Member Audio s))
  , coreKeyboard :: IORef (IM.IntMap (Member Keyboard s))
  , coreMouse :: IORef (IM.IntMap (Member Mouse s))
  , theTime :: MVar Time
  , theSystem :: G.System
  , targetFPS :: IORef Float
  , textures :: IORef (IM.IntMap G.Texture)
  , theEnd :: MVar ()
  }

instance MonadIO (System s) where
    liftIO m = mkSystem $ const m
    {-# INLINE liftIO #-}

instance MonadObjective (System s) where
  type Residence (System s) = System s
  data Address e (System s) = Control　Int (MVar (Object e (System s)))
  Control _ m .- e = mkSystem $ \fo -> push fo m e
  new c = mkSystem $ \fo -> do
    n <- takeMVar $ newObjectId fo
    mc <- newMVar c
    putMVar (newObjectId fo) (n + 1)
    return (Control n mc)

runGraphic :: Foundation s -> Time -> IO ()
runGraphic fo t0 = do
  fps <- readIORef (targetFPS fo)
  let t1 = t0 + 1/fps
  G.beginFrame (theSystem fo)
  ms <- readIORef (coreGraphic fo)
  pics <- forM (IM.elems ms) $ \(Member e m) -> push fo m $ e $ request (1/fps) -- is it appropriate?
  give (TextureStorage (textures fo)) $ mapM_ (drawSight fo) pics
  b <- G.endFrame (theSystem fo)
  
  Just t' <- GLFW.getTime
  threadDelay $ floor $ (t1 - realToFrac t') * 1000 * 1000

  tryTakeMVar (theEnd fo) >>= \case
      Just _ -> return ()
      _ | b -> putMVar (theEnd fo) ()
        | otherwise -> runGraphic fo t1

audioProcess :: Foundation s -> Int -> IO [V2 Float]
audioProcess fo n = do
  let dt = fromIntegral n / sampleRate fo
  ms <- readIORef (coreAudio fo)
  ws <- forM (IM.elems ms) $ \(Member e m) -> push fo m $ e $ request (dt, n)
  return $ foldr (zipWith (+)) (replicate n zero) ws

push :: Foundation s -> MVar (Object e (System s)) -> e a -> IO a
push fo mc e = do
  c0 <- takeMVar mc
  (a, c) <- unSystem fo $ runObject c0 e
  putMVar mc c
  return a

keyCallback :: Foundation s -> GLFW.KeyCallback
keyCallback fo _ k _ st _ = do
  ms <- readIORef (coreKeyboard fo)
  forM_ (IM.elems ms) $ \(Member e m) -> push fo m
    $ e $ request $ case st of
      GLFW.KeyState'Released -> Up (toEnum . fromEnum $ k :: Key)
      _ -> Down (toEnum . fromEnum $ k :: Key)

mouseButtonCallback :: Foundation s -> GLFW.MouseButtonCallback
mouseButtonCallback fo _ btn st _ = do
  ms <- readIORef (coreMouse fo)
  forM_ (IM.elems ms) $ \(Member e m) -> push fo m
    $ e $ request $ case st of
      GLFW.MouseButtonState'Released -> Button $ Up (fromEnum btn)
      _ -> Button $ Down (fromEnum btn)

cursorPosCallback :: Foundation s -> GLFW.CursorPosCallback
cursorPosCallback fo _ x y = do
  ms <- readIORef (coreMouse fo)
  forM_ (IM.elems ms) $ \(Member e m) -> push fo m $ e $ request $ Cursor $ fmap realToFrac $ V2 x y

scrollCallback :: Foundation s -> GLFW.ScrollCallback
scrollCallback fo _ x y = do
  ms <- readIORef (coreMouse fo)
  forM_ (IM.elems ms) $ \(Member e m) -> push fo m $ e $ request $ Scroll $ fmap realToFrac $ V2 x y

newtype TextureStorage = TextureStorage { getTextureStorage :: IORef (IM.IntMap G.Texture) }

drawScene :: Given TextureStorage => Foundation s -> Box V2 Float -> M44 Float -> Scene -> IO ()
drawScene fo (fmap round -> Box (V2 x0 y0) (V2 x1 y1)) proj (Scene s) = do
  GL.viewport $= (GL.Position x0 y0, GL.Size (x1 - x0) (y1 - y0))
  GL.UniformLocation loc <- GL.get (GL.uniformLocation shaderProg "projection")
  with proj $ \ptr -> GL.glUniformMatrix4fv loc 1 0 $ castPtr ptr
  s (pure $ return ()) (liftA2 (>>)) prim col trans (RGBA 1 1 1 1, 0)
  where
    shaderProg = G.theProgram $ theSystem fo
    prim Blank mode vs _ = do
      V.unsafeWith vs $ \v -> GL.bufferData GL.ArrayBuffer $=
        (fromIntegral $ V.length vs * sizeOf (undefined :: Vertex), v, GL.StaticDraw)
      GL.drawArrays mode 0 $ fromIntegral $ V.length vs
    prim (Bitmap bmp _ h) mode vs _ = do
      st <- readIORef (getTextureStorage given)
      (tex, _, _) <- case IM.lookup h st of
        Just t -> return t
        Nothing -> do
          t <- G.installTexture bmp
          writeIORef (getTextureStorage given) $ IM.insert h t st
          return t
      GL.texture GL.Texture2D $= GL.Enabled
      GL.textureFilter GL.Texture2D $= ((GL.Linear', Nothing), GL.Linear')
      GL.textureBinding GL.Texture2D $= Just tex
      
      V.unsafeWith vs $ \v -> GL.bufferData GL.ArrayBuffer $=
        (fromIntegral $ V.length vs * sizeOf (undefined :: Vertex), v, GL.StaticDraw)
      GL.drawArrays mode 0 $ fromIntegral $ V.length vs

      GL.texture GL.Texture2D $= GL.Disabled
    trans f m (color0, n) = do
      GL.UniformLocation loc <- GL.get $ GL.uniformLocation shaderProg "matrices"
      GL.UniformLocation locN <- GL.get $ GL.uniformLocation shaderProg "level" 
      with f $ \ptr -> GL.glUniformMatrix4fv (loc+n) 1 1 (castPtr ptr)
      GL.glUniform1i locN (unsafeCoerce $ n + 1)
      m (color0, n + 1)
    col f m (color0, n) = do
      GL.UniformLocation loc <- GL.get $ GL.uniformLocation shaderProg "color"
      let c = f color0
      with c $ \ptr -> GL.glUniform4iv loc 1 (castPtr ptr)
      m (c, n)
      with color0 $ \ptr -> GL.glUniform4iv loc 1 (castPtr ptr)      

drawSight :: Given TextureStorage => Foundation s -> Sight -> IO ()
drawSight fo (Sight s) = do
  b <- readIORef $ G.refRegion $ theSystem fo
  s b (return ()) (>>) (drawScene fo)
