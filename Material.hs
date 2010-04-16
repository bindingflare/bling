{-# LANGUAGE ExistentialQuantification #-}

module Material(Material(..), BsdfSample(..), intMaterial) where

import Geometry
import Light
import Math
import Random

class Material a where
   materialSample :: a -> Intersection -> Rand BsdfSample
   materialEval :: a -> Normal -> Normal -> Spectrum

data Matte = Matte Spectrum

instance Material Matte where
   materialEval (Matte r) wo wi = bsdfEval bsdf wo wi where
      bsdf = Lambertian r
      
   materialSample (Matte r) int = do
      s <- bsdfSample bsdf wi
      return (worldSample cs s)
      where
         wi = worldToLocal cs (intNorm int)
         cs = coordinates int
         bsdf = Lambertian r
      
intMaterial :: Intersection -> Matte
intMaterial i = Matte (0.7, 0.5, 0.3)

data BsdfSample = BsdfSample {
   bsdfSampleWi :: Normal,
   bsdfSamplePdf :: Float
   }

data ShadingCoordinates = ShadingCoordinates {
   nn :: Vector,
   sn :: Vector,
   tn :: Vector
   }

class Bsdf a where
   bsdfEval :: a -> Normal -> Normal -> Spectrum
   bsdfSample :: a -> Normal -> Rand BsdfSample
   bsdfPdf :: a -> Normal -> Normal -> Float
   
   bsdfSample a wo@(_, woy, _) = do
      wi' <- cosineSampleHemisphere
      return (BsdfSample (wif wi') (bsdfPdf a wo (wif wi')))
      where
            wif xx@(x, y, z)
               | woy < 0 = (x, -y, z)
               | otherwise = xx
   
   bsdfPdf _ wo wi@(_, z, _)
      | sameHemisphere wo wi = invPi * abs z
      | otherwise = 0

data AnyBsdf = forall a. Bsdf a => MkAnyBsdf a

instance Bsdf AnyBsdf where
   bsdfEval (MkAnyBsdf a) wo wi = bsdfEval a wo wi
   bsdfSample (MkAnyBsdf a) wo = bsdfSample a wo
   bsdfPdf (MkAnyBsdf a) wo wi = bsdfPdf a wo wi
   
data Lambertian = Lambertian {
   lambertionReflectance :: Spectrum
   }
   
instance Bsdf Lambertian where
   bsdfEval (Lambertian r) _ _ = scalMul r invPi

-- | decides if two vectors which must be in the shading coordinate system
-- are in the same hemisphere
sameHemisphere :: Vector -> Vector -> Bool
sameHemisphere (_, z1, _) (_, z2, _) = z1 * z2 > 0

coordinates :: Intersection -> ShadingCoordinates
coordinates (Intersection _ _ n) = (ShadingCoordinates n sn' tn') where
   (sn', tn') = coordinateSystem n

worldToLocal :: ShadingCoordinates -> Vector -> Vector
worldToLocal (ShadingCoordinates nn' sn' tn') v = (dot v sn', dot v tn', dot v nn')
   
worldSample :: ShadingCoordinates -> BsdfSample -> BsdfSample
worldSample sc (BsdfSample wi pdf) = (BsdfSample (localToWorld sc wi) pdf)
   
localToWorld :: ShadingCoordinates -> Vector -> Vector
localToWorld (ShadingCoordinates (nx, ny, nz) (sx, sy, sz) (tx, ty, tz)) (x, y, z) =
   (sx * x + tx * y + nx * z, sy * x + ty * y + ny * z, sz * x + tz * y + nz * z)
