

module Graphics.Bling.Integrator.Debug (
   mkKdVision, mkNormalMap, mkReference
   ) where


import Graphics.Bling.DifferentialGeometry
import Graphics.Bling.Integrator
--import Graphics.Bling.Montecarlo
import Graphics.Bling.Reflection
--import Graphics.Bling.Sampling
import Graphics.Bling.Scene
import Graphics.Bling.Primitive
-- import Graphics.Bling.Primitive.KdTree


--------------------------------------------------------------------------------
-- kd-tree vision integrator
--------------------------------------------------------------------------------

mkKdVision :: SurfaceIntegrator
mkKdVision = undefined -- KdTreeVis

mkNormalMap :: SurfaceIntegrator
mkNormalMap = SurfaceIntegrator li 0 0 where
   li s r = case s `scIntersect` r of
      Just int -> return $ intToSpectrum int
      Nothing  -> return black

   intToSpectrum :: Intersection -> Spectrum
   intToSpectrum int = rgbToSpectrumRefl (r, g, b) where
      Vector r g b = (vpromote 1 + n) / 2
      n = bsdfShadingNormal $ intBsdf int

mkReference :: SurfaceIntegrator
mkReference = undefined --Reference

{-
instance Printable DebugIntegrator where
   prettyPrint KdTreeVis = PP.text "kd tree vision"
   prettyPrint NormalMap = PP.text "Normal Map"
   prettyPrint Reference = PP.text "Reference"

instance SurfaceIntegrator DebugIntegrator where
   sampleCount1D _ = 0
   sampleCount2D _ = 0

   contrib KdTreeVis scene tell r = do
      let stats = dbgTraverse t r
      let ints = fromIntegral $ intersections stats
      li <- mkContrib (WS 1 (rgbToSpectrumRefl (fromIntegral $ nodesTraversed stats, ints, 0))) False
      liftSampled $ tell $ li
      where
         t = scenePrim scene

   contrib NormalMap scene tell ray = do
      if isJust mint
         then mkContrib (intToSpectrum (fromJust mint)) False >>= (liftSampled . tell)
         else return ()

      where
         mint = scene `intersect` ray

   contrib Reference scene tell ray = {-# SCC "contrib.Reference" #-}
         go ray >>= \(w,s) -> mkContrib (WS w s) False >>= (liftSampled . tell) where

      go r = maybe (return $ (0, black)) evalInt (scene `intersect` r) where
          evalInt int = let
                            p = bsdfShadingPoint bsdf
                            wo = -(rayDir r)
                            le = intLe int wo
                            bsdf = intBsdf int
                        in do
                           wi <- uniformSampleSphere `liftM` rnd2D
                           let
                              f = evalBsdf False bsdf wi wo

                           if isBlack f
                              then return $(1, le)
                              else do
                                 (_, rest) <- go $ Ray p wi (intEpsilon int) infinity
                                 return $ (1, (le + sScale (f * rest) (4 * pi)))


   -}
