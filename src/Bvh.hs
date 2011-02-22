{-# LANGUAGE ExistentialQuantification #-}

module Bvh 
   ( Bvh, mkBvh ) 
   where

import Data.Array
import Data.Maybe (isJust, isNothing, fromJust)

import AABB
import Math
import Primitive

type Bvh = TreeBvh

--
-- The BVH using the tree flattened out to an array
--

data LinearNode
   = LinearNode Dimension Int AABB
   | LinearLeaf AnyPrim AABB

data LinearBvh
   = MkLinearBvh (Array Int LinearNode)

instance Show LinearNode where
   show (LinearNode _ n _) = "node rc=" ++ show n
   show (LinearLeaf _ _) = "leaf"
   
-- instance Prim LinearNode where
   

flatten :: TreeBvh -> Int -> (Int, [LinearNode])
flatten (Leaf p b) n = (n + 1, [LinearLeaf p b])
flatten (Node d l r b) n = (nr, [LinearNode d nl b] ++ ll ++ lr) where
   (nl, ll) = flatten l (n + 1)
   (nr, lr) = flatten r nl

--
-- The simple "tree" BVH implementation
--

data TreeBvh
   = Node Dimension TreeBvh TreeBvh AABB
   | Leaf AnyPrim AABB

instance Prim TreeBvh where
   primIntersects = bvhIntersects
   primIntersect = bvhIntersect
   primWorldBounds (Node _ _ _ b) = b
   primWorldBounds (Leaf _ b) = b

mkBvh :: [AnyPrim] -> TreeBvh
mkBvh [p] = Leaf p $ primWorldBounds p
mkBvh ps = Node dim (mkBvh left) (mkBvh right) allBounds where
   (left, right) = splitMidpoint ps dim
   dim = splitAxis ps
   allBounds = foldl extendAABB emptyAABB $ map primWorldBounds ps

bvhIntersect :: TreeBvh -> Ray -> Maybe Intersection
bvhIntersect (Leaf p b) ray
   | isNothing $ intersectAABB b ray = Nothing
   | otherwise = primIntersect p ray
bvhIntersect (Node d l r b) ray@(Ray ro rd tmin tmax)
   | isNothing $ intersectAABB b ray = Nothing
   | otherwise = near firstInt otherInt where
      (firstChild, otherChild) = if component rd d > 0 then (l, r) else (r, l)
      firstInt = bvhIntersect firstChild ray
      tmax'
	 | isJust firstInt = intDist $ fromJust firstInt
	 | otherwise = tmax
      otherInt = bvhIntersect otherChild $ Ray ro rd tmin tmax'

near :: Maybe Intersection -> Maybe Intersection -> Maybe Intersection
near Nothing i = i
near i Nothing = i
near mi1 mi2 = Just $ near' (fromJust mi1) (fromJust mi2) where
   near' i1@(Intersection d1 _ _ _) i2@(Intersection d2 _ _ _)
      | d1 < d2 = i1
      | otherwise = i2

bvhIntersects :: TreeBvh -> Ray -> Bool
bvhIntersects (Leaf p b) r = isJust (intersectAABB b r) && primIntersects p r
bvhIntersects (Node _ l r b) ray = isJust (intersectAABB b ray) &&
   (bvhIntersects l ray || bvhIntersects r ray)

-- | Splits the given @Primitive@ list along the specified @Dimension@
--   in two lists
splitMidpoint :: [AnyPrim] -> Dimension -> ([AnyPrim], [AnyPrim])
splitMidpoint ps dim = ([l | l <- ps, toLeft l], [r | r <- ps, not $ toLeft r]) where
   toLeft p = component (centroid $ primWorldBounds p) dim < pMid
   pMid = 0.5 * (component (aabbMin cb) dim + component (aabbMax cb) dim)
   cb = centroidBounds ps

-- | Finds the preferred split axis for a list of primitives. This
--   is where the AABBs centroid's bounds have the maximum extent
splitAxis :: [AnyPrim] -> Dimension
splitAxis = maximumExtent . centroidBounds

-- | Finds the AABB of the specified @Primitive@'s centroids
centroidBounds :: [AnyPrim] -> AABB
centroidBounds ps = foldl extendAABBP emptyAABB $ centroids ps

-- | Finds the centroids of a list of primitives
centroids :: [AnyPrim] -> [Point]
centroids = map (centroid . primWorldBounds)