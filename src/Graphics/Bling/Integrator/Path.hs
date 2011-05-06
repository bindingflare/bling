
module Graphics.Bling.Integrator.Path (
   mkPathIntegrator, PathIntegrator
   ) where

import Data.BitSet
import qualified Data.Vector.Generic as V
import qualified Text.PrettyPrint as PP

import Graphics.Bling.Integrator
import Graphics.Bling.Light
import Graphics.Bling.Math
import Graphics.Bling.Primitive
import Graphics.Bling.Reflection
import Graphics.Bling.Sampling
import Graphics.Bling.Scene
import Graphics.Bling.Spectrum

data PathIntegrator = PathIntegrator {-# UNPACK #-} !Int

mkPathIntegrator :: Int -> PathIntegrator
mkPathIntegrator = PathIntegrator


smps2D :: Int
smps2D = 1

smp2doff :: Int -> Int
smp2doff d = smps2D * d


instance SurfaceIntegrator PathIntegrator where
   li (PathIntegrator md) s r =
      nextVertex s 0 True r (s `intersect` r) white black md
      
   pp (PathIntegrator md) =
      PP.text ("Path Integrator " ++ (show md))
   
nextVertex :: Scene -> Int -> Bool -> Ray -> Maybe Intersection -> Spectrum -> Spectrum -> Int -> Sampled WeightedSpectrum

-- nothing hit, specular bounce
nextVertex s _ True ray Nothing t l _ = 
   return (1, l + t * V.sum (V.map (`le` ray) (sceneLights s)))
   
-- nothing hit, non-specular bounce
nextVertex _ _ False _ Nothing _ l _ = 
   return (1, l)

nextVertex scene depth spec (Ray _ rd _ _) (Just int) t l md
   | isBlack t || depth == md = return (1, l)
   | otherwise = do
      bsdfDirU <- rnd2D' $ smp2doff depth
      bsdfCompU <- rnd
      let (BsdfSample smpType spdf f wi) = sampleBsdf bsdf wo bsdfCompU bsdfDirU
      ulNum <- rnd
      lHere <- sampleOneLight scene p n wo bsdf ulNum
      let l' = l + (t * (lHere + intl))
      
      rnd >>= \x -> if x > pc || (spdf == 0) || isBlack f
         then return $! (1.0, l')
         else let
                 t' = t * sScale f (absDot wi n / (spdf * pc))
                 spec' = Specular `member` smpType
                 ray' = (Ray p wi epsilon infinity)
                 int' = intersect (scenePrim scene) ray'
                 depth' = depth + 1
              in nextVertex scene depth' spec' ray' int' t' l' md
      
      where
         dg = intGeometry int
         pc = if depth <= 3 then 1 else min 0.5 (sY t) -- cont. probability
         intl = if spec then intLe int wo else black
         wo = -rd
         bsdf = intBsdf int
         n = dgN dg
         p = dgP dg

