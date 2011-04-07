
module Graphics.Bling.AABB (
   AABB(..), mkAABB,
   emptyAABB, extendAABB, extendAABBP, maximumExtent, centroid, intersectAABB
) where

import Graphics.Bling.Math

-- | an axis-aligned bounding box
data AABB = AABB {
   aabbMin :: Point, -- ^ the box' minimum
   aabbMax :: Point  -- ^ the box' maximum
   }

instance Show AABB where
   show b = "AABB [min=" ++ show (aabbMin b) ++ ", max="
      ++ show (aabbMax b) ++ "]"

emptyAABB :: AABB
{-# INLINE emptyAABB #-}
emptyAABB = AABB
   (Vector infinity infinity infinity)
   (Vector (-infinity) (-infinity) (-infinity))

mkAABB :: Point -> Point -> AABB
{-# INLINE mkAABB #-}
mkAABB pMin pMax = AABB pMin pMax

extendAABB :: AABB -> AABB -> AABB
{-# INLINE extendAABB #-}
extendAABB
   (AABB (Vector min1x min1y min1z) (Vector max1x max1y max1z))
   (AABB (Vector min2x min2y min2z) (Vector max2x max2y max2z)) =
   AABB
      (Vector (min min1x min2x) (min min1y min2y) (min min1z min2z))
      (Vector (max max1x max2x) (max max1y max2y) (max max1z max2z))

extendAABBP :: AABB -> Point -> AABB
{-# INLINE extendAABBP #-}
extendAABBP (AABB pMin pMax) p = AABB (f min pMin p) (f max pMax p) where
   f cmp (Vector x1 y1 z1) (Vector x2 y2 z2) = Vector (cmp x1 x2) (cmp y1 y2) (cmp z1 z2)

-- | finds the @Dimension@ along which an @AABB@ has it's maximum extent
maximumExtent :: AABB -> Dimension
{-# INLINE maximumExtent #-}
maximumExtent (AABB pmin pmax) = dominant $ pmax - pmin

centroid :: AABB -> Point
{-# INLINE centroid #-}
centroid (AABB pmin pmax) = pmin + (pmax - pmin) * 0.5 

intersectAABB :: AABB -> Ray -> Maybe (Flt, Flt)
{-# INLINE intersectAABB #-}
intersectAABB (AABB bMin bMax) (Ray o d tmin tmax) = testSlabs allDimensions tmin tmax where
   testSlabs :: [Dimension] -> Flt -> Flt -> Maybe (Flt, Flt)
   testSlabs [] n f
      | n > f = Nothing
      | otherwise = Just (n, f)
   testSlabs (dim:ds) near far
      | near > far = Nothing
      | otherwise = testSlabs ds (max near near') (min far far') where
	 (near', far') = if tNear > tFar then (tFar, tNear) else (tNear, tFar)
	 tFar = ((component bMax dim) - oc) * dInv
	 tNear = ((component bMin dim) - oc) * dInv
	 oc = component o dim
	 dInv = 1 / (component d dim)
   