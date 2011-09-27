{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleContexts #-}

module Graphics.Bling.Random (

   -- * managing the random number generator
   
   Rand, liftR, Rand2D, runRand, runRandIO, runWithSeed, ioSeed, intSeed,
      
   -- * generating random values
   
   rnd2D, rnd, rndList, rndList2D, rndInt, rndIntR, rndIntList, shuffle,

   -- * State in the Rand Monad

   newRandRef, readRandRef, writeRandRef, modifyRandRef
   ) where

import Control.Monad (forM_, replicateM)
import Control.Monad.Primitive
import Control.Monad.ST
import Data.STRef
import qualified Data.Vector as V
import qualified Data.Vector.Unboxed.Mutable as MV
import qualified System.Random.MWC as MWC

type Rand2D = (Float, Float)

-- | Marks a computation that requires random values
newtype Rand s a = Rand {
   runRand :: MWC.Gen (PrimState (ST s)) -> ST s a
   }
   
-- | For allowing the Monadic syntax when using @Rand@
instance Monad (Rand s) where
   return k = Rand (\ _ -> return k)
   Rand c1 >>= fc2 = Rand (\ g -> c1 g >>= \a -> runRand (fc2 a) g)
   {-# INLINE return #-}
   {-# INLINE (>>=)  #-}

-- | Run monad using seed
runWithSeed :: MWC.Seed -> Rand s a -> ST s a
runWithSeed seed m = runRand m =<< MWC.restore seed
{-# INLINE runWithSeed #-}

-- | create a new seed using the system's random source
ioSeed :: IO MWC.Seed
ioSeed = MWC.withSystemRandom $ do
   s' <- MWC.save :: MWC.Gen (PrimState IO) -> IO MWC.Seed
   return s'

intSeed :: [Int] -> MWC.Seed
intSeed seed = runST $ do
      g <- MWC.initialize (V.fromList $ map fromIntegral seed)
      s <- MWC.save g -- :: MWC.Gen (PrimState (ST s)) -> ST s MWC.Seed
      return s

runRandIO :: Rand RealWorld a -> IO a
runRandIO = MWC.withSystemRandom . runRand
{-# INLINE runRandIO #-}

liftR :: ST s a -> Rand s a
{-# INLINE liftR #-}
liftR m = Rand $ const m

-- | shuffles the given mutable vector in-place
-- shuffle :: (MV.MVector v a) => v s a -> Rand s ()
{-# INLINE shuffle #-}
shuffle v = do
   forM_ [0..n-1] $ \i -> do
      other <- rndIntR (0, n - i - 1)
      liftR $ MV.unsafeSwap v i (other + i)
   where
      n = MV.length v

-- | Provides a random @Float@ in @[0..1)@
rnd :: Rand s Float
{-# INLINE rnd #-}
rnd = do
   u <- Rand MWC.uniform
   return $ u - 2**(-33)

rndInt :: Rand s Int
{-# INLINE rndInt #-}
rndInt = Rand MWC.uniform

rndIntR :: (Int, Int) -> Rand s Int
{-# INLINE rndIntR #-}
rndIntR r = Rand $ MWC.uniformR r

rndIntList
   :: Int
   -> Rand s [Int]
rndIntList n = replicateM n $ rndInt

-- | generates a list of given length of random numbers in [0..1)
rndList
   :: Int -- ^ the length of the list to generate
   -> Rand s [Float]
rndList n = replicateM n $ rnd
{-# INLINE rndList #-}

-- | generates a list of given length containing tuples of random numbers
rndList2D
   :: Int -- the length of the list to generate
   -> Rand s [Rand2D]
rndList2D n = do
   us <- rndList n
   vs <- rndList n
   return $ Prelude.zip us vs
{-# INLINE rndList2D #-}

rnd2D :: Rand s Rand2D
{-# INLINE rnd2D #-}
rnd2D = do
   u1 <- rnd
   u2 <- rnd
   return (u1, u2)

--------------------------------
-- STRefs in Rand
------------------------------------

newRandRef :: a -> Rand s (STRef s a)
{-# INLINE newRandRef #-}
newRandRef x = liftR $ newSTRef x

readRandRef :: STRef s a -> Rand s a
{-# INLINE readRandRef #-}
readRandRef = liftR . readSTRef

writeRandRef :: STRef s a -> a -> Rand s ()
{-# INLINE writeRandRef #-}
writeRandRef r a = liftR $ writeSTRef r a

modifyRandRef :: STRef s a -> (a -> a) -> Rand s ()
{-# INLINE modifyRandRef #-}
modifyRandRef r f = liftR $ modifySTRef r f

