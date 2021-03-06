{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}

module Graphics.Bling.Math (
   module Graphics.Bling.Types,

   -- * Constants

   twoPi, invPi, invTwoPi, infinity,

   -- * Basic Functions

   lerp, remapRand, clamp, radians, solveQuadric, atan2',

   -- * Vectors

   Vector(..), mkV, mkV', vpromote, dot, cross, normalize, normLen, absDot,
   len, sqLen,
   Normal, mkNormal, Point, mkPoint, mkPoint',
   Dimension, allDimensions, setComponent, (.!), dominant, dimX, dimY, dimZ,
   sphericalDirection, sphericalTheta, sphericalPhi, faceForward,
   sphToDir, dirToSph, sphSinTheta, (*#),

   -- * Rays

   Ray(..), normalizeRay, rayAt, onRay,

   -- * Otrth. Basis
   LocalCoordinates(..), worldToLocal, localToWorld, coordinateSystem,
   coordinateSystem', coordinateSystem''

   ) where

import Control.Monad (liftM)
import qualified Data.Vector.Unboxed as V
import qualified Data.Vector.Generic as GV
import qualified Data.Vector.Generic.Mutable as MV

import Graphics.Bling.Types

--
-- Utility functions
--

infinity :: Float
{-# INLINE infinity #-}
infinity = 1 / 0

invPi :: Float
{-# INLINE invPi #-}
invPi = 1 / pi

invTwoPi :: Float
{-# INLINE invTwoPi #-}
invTwoPi = 1 / (2 * pi)

twoPi :: Float
{-# INLINE twoPi #-}
twoPi = 2.0 * pi

-- | converts an angle from degrees to radians
radians
   :: Float -- ^ the angle in degrees
   -> Float -- ^ the angle in radions
{-# INLINE radians #-}
radians x = (x / 180 * pi)

-- | like @atan2@, but returns positive values in [0..2pi]
atan2' :: Float -> Float -> Float
{-# INLINE atan2' #-}
atan2' y x
   | a < 0 = a + twoPi
   | otherwise = a
   where
      a = atan2 y x

-- | clamps a value so it is withing a specified range
clamp
   :: Float -- ^ the value to clamp
   -> Float -- ^ the lower bound
   -> Float -- ^ the upper bound
   -> Float
{-# INLINE clamp #-}
clamp v lo hi
   | v < lo = lo
   | v > hi = hi
   | otherwise = v

-- | Defines names for the three axii
type Dimension = Int

dimX :: Dimension

dimX = 0
{-# INLINE dimX #-}
dimY :: Dimension

dimY = 1
{-# INLINE dimY #-}

dimZ :: Dimension
{-# INLINE dimZ #-}
dimZ = 2

allDimensions :: [Dimension]
allDimensions = [dimX, dimY, dimZ]

lerp :: Float -> Float -> Float -> Float
{-# INLINE lerp #-}
lerp t v1 v2 = (1 - t) * v1 + t * v2

-- remaps a random variable in [0, 1) to a number of strata
remapRand
   :: Int -- ^ the number of strata to remap to
   -> Float -- ^ the variate to remap
   -> (Int, Float) -- ^ (selected stratum, remapped variate)
{-# INLINE remapRand #-}
remapRand segs u = (seg, u') where
   seg = min (segs-1) (floor $ u * segs')
   segs' = fromIntegral segs
   u' = (u - fromIntegral seg / segs') * segs'

-- | find the roots of a * x^2 + b * x + c = 0
solveQuadric
   :: Float -- ^ parameter a
   -> Float -- ^ parameter b
   -> Float -- ^ parameter c
   -> Maybe (Float, Float)
{-# INLINE solveQuadric #-}
solveQuadric a b c
   | discrim < 0 = Nothing
   | otherwise = Just (min t0 t1, max t0 t1)
   where
         (t0, t1) = (q / a, c / q)
         q
            | b < 0 = -0.5 * (b - rootDiscrim)
            | otherwise = -0.5 * (b + rootDiscrim)
         rootDiscrim = sqrt discrim
         discrim = b * b - 4 * a * c

sphericalDirection :: Float -> Float -> Float -> Vector
{-# INLINE sphericalDirection #-}
sphericalDirection sint cost phi = Vector (sint * cos phi) (sint * sin phi) cost

-- | converts from spherical coordinates to a direction vector
sphToDir :: SphericalCoords -> Vector
{-# INLINE sphToDir #-}
sphToDir (Spherical (p, t)) = sphericalDirection (sin t) (cos t) p

dirToSph :: Vector -> SphericalCoords
{-# INLINE dirToSph #-}
dirToSph v = Spherical (sphericalPhi v, sphericalTheta v)

-- | returns the sine of the theta component of @SphericalCoords@
sphSinTheta :: SphericalCoords -> Float
{-# INLINE sphSinTheta #-}
sphSinTheta (Spherical (_, t)) = sin t

sphericalTheta :: Vector -> Float
{-# INLINE sphericalTheta #-}
sphericalTheta (Vector _ _ z) = acos $ max (-1) $ min 1 z

sphericalPhi :: Vector -> Float
{-# INLINE sphericalPhi #-}
sphericalPhi (Vector x y _)
   | p' < 0 = p' + 2 * pi
   | otherwise = p'
   where
         p' = atan2 y x

--------------------------------------------------------------------------------
-- Vectors
--------------------------------------------------------------------------------

data Vector = Vector { vx, vy, vz :: {-# UNPACK #-} !Float } deriving ( Eq )

vzip :: (Float -> Float -> Float) -> Vector -> Vector -> Vector
{-# INLINE vzip #-}
vzip f (Vector x1 y1 z1) (Vector x2 y2 z2) =
   Vector (f x1 x2) (f y1 y2) (f z1 z2)

vmap :: (Float -> Float) -> Vector -> Vector
{-# INLINE vmap #-}
vmap f (Vector x y z) = Vector (f x) (f y) (f z)

vpromote :: Float -> Vector
{-# INLINE vpromote #-}
vpromote x = Vector x x x

instance Show Vector where
   show (Vector x y z) = "(" ++ show x ++ ", " ++
      show y ++ ", " ++ show z ++ ")"

instance Num Vector where
   (+) = vzip (+)
   (-) = vzip (-)
   (*) = vzip (*)
   abs = vmap abs
   signum = vmap signum
   fromInteger = vpromote . fromInteger

instance Fractional Vector where
  (/) = vzip (/)
  recip = vmap recip
  fromRational = vpromote . fromRational

(*#) :: Float -> Vector -> Vector
{-# INLINE (*#) #-}
(*#) f v = vpromote f * v

-- make Vector an instance of Unbox

newtype instance V.MVector s Vector = MV_Vector (V.MVector s Float)
newtype instance V.Vector Vector = V_Vector (V.Vector Float)

instance V.Unbox Vector

instance MV.MVector V.MVector Vector where
   basicLength (MV_Vector v) = MV.basicLength v `div` 3
   {-# INLINE basicLength #-}

   basicUnsafeSlice s l (MV_Vector v) =
      MV_Vector (MV.unsafeSlice (s * 3) (l * 3) v)
   {-# INLINE basicUnsafeSlice #-}

   basicUnsafeNew l = MV_Vector `liftM` MV.unsafeNew (l * 3)
   {-# INLINE basicUnsafeNew #-}

   basicInitialize _ = return ()

   basicOverlaps (MV_Vector v1) (MV_Vector v2) = MV.overlaps v1 v2
   {-# INLINE basicOverlaps #-}

   basicUnsafeRead (MV_Vector v) idx = do
      x <- MV.unsafeRead v idx'
      y <- MV.unsafeRead v (idx' + 1)
      z <- MV.unsafeRead v (idx' + 2)
      return $ Vector x y z
      where
         idx' = idx * 3
   {-# INLINE basicUnsafeRead #-}

   basicUnsafeWrite (MV_Vector v) idx (Vector x y z) = do
      MV.unsafeWrite v (idx' + 0) x
      MV.unsafeWrite v (idx' + 1) y
      MV.unsafeWrite v (idx' + 2) z
      where
         idx' = idx * 3
   {-# INLINE basicUnsafeWrite #-}

instance GV.Vector V.Vector Vector where
   basicLength (V_Vector v) = GV.basicLength v `div` 3
   {-# INLINE basicLength #-}

   basicUnsafeSlice s l (V_Vector v) =
      V_Vector $ (GV.unsafeSlice (s * 3) (l * 3) v)
   {-# INLINE basicUnsafeSlice #-}

   basicUnsafeFreeze (MV_Vector v) = V_Vector `liftM` (GV.unsafeFreeze v)
   {-# INLINE basicUnsafeFreeze #-}

   basicUnsafeThaw (V_Vector v) = MV_Vector `liftM` (GV.unsafeThaw v)
   {-# INLINE basicUnsafeThaw #-}

   basicUnsafeIndexM (V_Vector v) idx = do
      x <- GV.unsafeIndexM v (idx' + 0)
      y <- GV.unsafeIndexM v (idx' + 1)
      z <- GV.unsafeIndexM v (idx' + 2)
      return $ Vector x y z
      where
         idx' = idx * 3
   {-# INLINE basicUnsafeIndexM #-}

-- types derieved from Vector

type Point = Vector

mkPoint :: (Float, Float, Float) -> Point
{-# INLINE mkPoint #-}
mkPoint (x, y, z) = Vector x y z

mkPoint' :: Float -> Float -> Float -> Point
{-# INLINE mkPoint' #-}
mkPoint' = Vector

type Normal = Vector

mkNormal :: Float -> Float -> Float -> Normal
{-# INLINE mkNormal #-}
mkNormal = Vector

dominant :: Vector -> Dimension
{-# INLINE dominant #-}
dominant (Vector x y z)
   | (ax > ay) && (ax > az) = dimX
   | ay > az = dimY
   | otherwise = dimZ
   where
      ax = abs x
      ay = abs y
      az = abs z

mkV :: (Float, Float, Float) -> Vector
{-# INLINE mkV #-}
mkV (x, y, z) = Vector x y z

mkV' :: Float -> Float -> Float -> Vector
mkV' = Vector

component :: Vector -> Dimension -> Float
{-# INLINE component #-}
component (Vector x y z) d
   | d == dimX = x
   | d == dimY = y
   | otherwise = z

(.!) :: Vector -> Dimension -> Float
{-# INLINE (.!) #-}
(.!) = component

setComponent :: Dimension -> Float -> Vector -> Vector
{-# INLINE setComponent #-}
setComponent dim t (Vector x y z)
   | dim == dimX  = mkPoint' t y z
   | dim == dimY  = mkPoint' x t z
   | otherwise    = mkPoint' x y t

sqLen :: Vector -> Float
{-# INLINE sqLen #-}
sqLen (Vector x y z) = x*x + y*y + z*z

len :: Vector -> Float
{-# INLINE len #-}
len v = sqrt (sqLen v)

cross :: Vector -> Vector -> Vector
{-# INLINE cross #-}
cross (Vector ux uy uz) (Vector x2 y2 z2) =
   Vector (uy*z2 - uz*y2) (-(ux*z2 - uz*x2)) (ux*y2 - uy*x2)

dot :: Vector -> Vector -> Float
{-# INLINE dot #-}
dot (Vector x y z) (Vector a b c) =  x*a + y*b + z*c;

absDot :: Vector -> Vector -> Float
{-# INLINE absDot #-}
absDot v1 v2 = abs (dot v1 v2)

normalize :: Vector -> Normal
{-# INLINE normalize #-}
normalize v
  | sqLen v /= 0 = v * vpromote (1 / len v)
  | otherwise = Vector 0 1 0

-- | normalizes a vector and returns the length of the original vector
normLen :: Vector -> (Vector, Float)
{-# INLINE normLen #-}
normLen v
   | sqLen v /= 0 = (v * vpromote (1 / l), l)
   | otherwise = (v, 0)
   where
      l2 = sqLen v
      l = sqrt l2

faceForward :: Vector -> Vector -> Vector
{-# INLINE faceForward #-}
faceForward v v2
   | v `dot` v2 < 0 = -v
   | otherwise = v

--------------------------------------------------------------------------------
-- Rays
--------------------------------------------------------------------------------

data Ray = Ray {
   rayOrigin :: {-# UNPACK #-} ! Point,
   rayDir :: {-# UNPACK #-} ! Normal,
   rayMin :: {-# UNPACK #-} ! Float,
   rayMax :: {-# UNPACK #-} ! Float
   } deriving Show

-- | Creates a ray that connects the two specified points.
-- segmentRay :: Point -> Point -> Ray
-- {-# INLINE segmentRay #-}
-- segmentRay p1 p2 = Ray p1 p1p2 epsilon (1 - epsilon) where
--   p1p2 = p2 - p1

rayAt :: Ray -> Float -> Point
{-# INLINE rayAt #-}
rayAt (Ray o d _ _) t = o + (d * vpromote t)

-- | decides if a @t@ value is in the ray's bounds
onRay :: Ray -> Float -> Bool
{-# INLINE onRay #-}
onRay (Ray _ _ tmin tmax) t = t >= tmin && t <= tmax

-- | normalizes the direction component of a @Ray@ and adjusts the
-- min/max values accordingly
normalizeRay :: Ray -> Ray
{-# INLINE normalizeRay #-}
normalizeRay (Ray ro rd rmin rmax) = Ray ro rd' rmin' rmax' where
   l = len rd
   rmin' = rmin * l
   rmax' = rmax * l
   rd' = rd * vpromote (1 / l)

-- | an orthonormal basis
data LocalCoordinates = LocalCoordinates
    ! Vector
    ! Vector
    ! Vector

coordinateSystem :: Vector -> LocalCoordinates
{-# INLINE coordinateSystem #-}
coordinateSystem v@(Vector x y z)
   | abs x > abs y =
      let
          invLen = 1.0 / sqrt (x*x + z*z)
          v2 = Vector (-z * invLen) 0 (x * invLen)
      in LocalCoordinates v2 (cross v v2) v
   | otherwise =
      let
          invLen = 1.0 / sqrt (y*y + z*z)
          v2 = Vector 0 (z * invLen) (-y * invLen)
      in LocalCoordinates v2 (cross v v2) v

coordinateSystem' :: Vector -> Vector -> LocalCoordinates
{-# INLINE coordinateSystem' #-}
coordinateSystem' w v = LocalCoordinates u v' w' where
   w' = normalize w
   u = normalize $ v `cross` w'
   v' = w' `cross` u

coordinateSystem'' :: Vector -> (Vector, Vector)
{-# INLINE coordinateSystem'' #-}
coordinateSystem'' v = (du, dv) where
   (LocalCoordinates du dv _) = coordinateSystem v

worldToLocal :: LocalCoordinates -> Vector -> Vector
{-# INLINE worldToLocal #-}
worldToLocal (LocalCoordinates sn tn nn) v = Vector (dot v sn) (dot v tn) (dot v nn)

localToWorld :: LocalCoordinates -> Vector -> Vector
{-# INLINE localToWorld #-}
localToWorld (LocalCoordinates (Vector sx sy sz) (Vector tx ty tz) (Vector nx ny nz)) (Vector x y z) =
   Vector
      (sx * x + tx * y + nx * z)
      (sy * x + ty * y + ny * z)
      (sz * x + tz * y + nz * z)
