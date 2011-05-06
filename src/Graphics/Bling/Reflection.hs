{-# LANGUAGE ExistentialQuantification #-}

module Graphics.Bling.Reflection (

   -- * Material

   Material, blackBodyMaterial,
   
   -- * Fresnel Equations
   
   Fresnel, frDielectric, frConductor, frNoOp,
   
   -- * Microfacet Distributions
   
   Microfacet(..), Distribution(..),

   -- * BxDF Functions

   AnyBxdf(..), Bxdf(..), BxdfProp(..), BxdfType, mkBxdfType,
   Lambertian(..), mkOrenNayar, OrenNayar,
   
   -- * BSDF
   
   Bsdf, BsdfSample(..),
   mkBsdf, evalBsdf, sampleBsdf, bsdfPdf,
   
   -- * Working with Vectors in shading coordinate system

   cosTheta, absCosTheta, sinTheta2, sinTheta, cosPhi, sinPhi,
   sameHemisphere, shadingCs
   
   ) where


import Data.BitSet
import Data.List (foldl')
import qualified Data.Vector as V

import Graphics.Bling.Math
import Graphics.Bling.Random
import Graphics.Bling.Spectrum

type Material = DifferentialGeometry -> Bsdf

type Fresnel = Flt -> Spectrum

frNoOp :: Fresnel
frNoOp _ = white

frDielectric :: Flt -> Flt -> Fresnel
frDielectric etai etat cosi
   | sint >= 1 = white -- total internal reflection
   | otherwise = frDiel' (abs cosi') cost (sConst ei) (sConst et)
   where
      cost = sqrt $ max 0 (1 - sint * sint)
      sint = (ei / et) * sqrt (max 0 (1 - cosi' * cosi'))
      cosi' = clamp cosi (-1) 1
      (ei, et) = if cosi' > 0 then (etai, etat) else (etat, etai)
   
frDiel' :: Flt -> Flt -> Spectrum -> Spectrum -> Spectrum
frDiel' cosi cost etai etat = (rPar * rPar + rPer * rPer) / 2 where
   rPar = (sScale etat cosi - sScale etai cost) /
          (sScale etat cosi + sScale etai cost)
   rPer = (sScale etai cosi - sScale etat cost) /
          (sScale etai cosi + sScale etat cost)

frConductor :: Spectrum -> Spectrum -> Fresnel
frConductor eta k cosi = (rPer2 + rPar2) / 2.0 where
   rPer2 = (tmpF - ec2 + sConst (cosi * cosi)) /
                (tmpF + ec2 + sConst (cosi * cosi))
   rPar2 = (tmp - ec2 + white) /
                (tmp + ec2 + white)
   ec2 = sScale eta (2 * cosi)
   tmp = sScale (eta * eta + k * k) (cosi * cosi)
   tmpF = eta * eta + k * k

cosTheta :: Vector -> Flt
cosTheta = vz

absCosTheta :: Vector -> Flt
absCosTheta = abs . vz

sinTheta2 :: Vector -> Flt
sinTheta2 v = max 0 (1 - cosTheta v * cosTheta v)

sinTheta :: Vector -> Flt
sinTheta = sqrt . sinTheta2

cosPhi :: Vector -> Flt
cosPhi v
   | sint == 0 = 1
   | otherwise = clamp (vx v / sint) (-1) 1
   where
         sint = sinTheta v

sinPhi :: Vector -> Flt
sinPhi v
   | sint == 0 = 0
   | otherwise = clamp (vy v / sint) (-1) 1
   where
         sint = sinTheta v


-- | decides if two vectors in shading coordinate system lie within the
--   same hemisphere
sameHemisphere :: Vector -> Vector -> Bool
sameHemisphere (Vector _ _ z1) (Vector _ _ z2) = z1 * z2 > 0


data BxdfProp = Transmission | Reflection | Diffuse | Glossy | Specular deriving (Eq, Enum, Show)

type BxdfType = BitSet BxdfProp

toSameHemisphere :: Vector -> Vector -> Vector
toSameHemisphere wo wi = if vz wo < 0 then wi {vz = -(vz wi)} else wi

class Bxdf a where
   bxdfEval :: a -> Normal -> Normal -> Spectrum
   bxdfSample :: a -> Normal -> Rand2D -> (Spectrum, Normal, Flt)
   bxdfPdf :: a -> Normal -> Normal -> Flt
   bxdfType :: a -> BxdfType

   bxdfSample a wo u = (f, wi, pdf) where
      wi = toSameHemisphere wo (cosineSampleHemisphere u)
      f = bxdfEval a wo wi
      pdf = bxdfPdf a wo wi
      
      
   bxdfPdf _ (Vector _ _ woz) (Vector _ _ wiz)
      | woz * wiz > 0 = invPi * abs wiz
      | otherwise = 0

data AnyBxdf = forall a. Bxdf a => MkAnyBxdf a

instance Bxdf AnyBxdf where
   bxdfEval (MkAnyBxdf a) = bxdfEval a
   bxdfSample (MkAnyBxdf a) = bxdfSample a
   bxdfPdf (MkAnyBxdf a) = bxdfPdf a
   bxdfType (MkAnyBxdf a) = bxdfType a

isDiffuse :: (Bxdf b) => b -> Bool
isDiffuse b = Diffuse `member` bxdfType b

isReflection :: (Bxdf b) => b -> Bool
isReflection b = Reflection `member` bxdfType b

isTransmission :: (Bxdf b) => b -> Bool
isTransmission b = Transmission `member` bxdfType b

isSpecular :: (Bxdf b) => b -> Bool
isSpecular b = Specular `member` bxdfType b

mkBxdfType :: [BxdfProp] -> BxdfType
mkBxdfType = foldl' (flip insert) empty

data Bsdf = Bsdf (V.Vector AnyBxdf) LocalCoordinates

shadingCs :: DifferentialGeometry -> LocalCoordinates
{-# INLINE shadingCs #-}
shadingCs dg = coordinateSystem $ dgN dg

data BsdfSample = BsdfSample {
   bsdfSampleType :: BxdfType,
   bsdfSamplePdf :: Float,
   bsdfSampleTransport :: Spectrum,
   bsdfSampleWi :: Vector
   } deriving (Show)


-- | filters a Bsdf's components by appearance
filterBsdf :: BxdfProp -> Bsdf -> Bsdf
filterBsdf ap (Bsdf bs cs) = Bsdf bs' cs where
   bs' = V.filter (member ap . bxdfType) bs

bsdfPdf :: Bsdf -> Vector -> Vector -> Float
bsdfPdf (Bsdf bs cs) woW wiW
   | V.null bs = 0
   | otherwise = V.sum $ V.map (\b -> bxdfPdf b wo wi) bs where
      wo = worldToLocal cs woW
      wi = worldToLocal cs wiW
      
sampleBsdf :: Bsdf -> Vector -> Float -> Rand2D -> BsdfSample
sampleBsdf (Bsdf bs cs) woW uComp uDir
   | V.null bs || pdf' == 0 = emptyBsdfSample
   | isSpecular bxdf = BsdfSample t pdf' f' wiW
   | otherwise = BsdfSample t pdf f wiW where
      f = V.foldl' (+) f' $ V.map (\b -> bxdfEval b wo wi) bs'
      pdf = (V.sum $ V.map (\ b -> bxdfPdf b wo wi) bs) / (fromIntegral cnt)
      bs' = V.ifilter (\ i _ -> (i /= sNum)) bs -- filter explicitely sampled
      (f', wi, pdf') = bxdfSample bxdf wo uDir
      wiW = localToWorld cs wi
      wo = worldToLocal cs woW
      bxdf = V.unsafeIndex bs sNum
      sNum = min (cnt-1) (floor (uComp * fromIntegral cnt)) -- index to sample
      cnt = V.length bs
      t = bxdfType bxdf
      
evalBsdf :: Bsdf -> Vector -> Vector -> Spectrum
evalBsdf (Bsdf bxdfs sc@(LocalCoordinates _ _ n)) woW wiW =
   V.foldl' (+) black $ V.map (\b -> bxdfEval b wo wi) $ V.filter flt bxdfs
   where
         flt = if dot woW n * dot wiW n < 0 then isTransmission else isReflection
         wo = worldToLocal sc woW
         wi = worldToLocal sc wiW


emptyBsdfSample :: BsdfSample
emptyBsdfSample = BsdfSample (mkBxdfType [Reflection, Diffuse]) 0 black (Vector 0 1 0)

blackBodyMaterial :: Material
blackBodyMaterial dg = mkBsdf [] $ shadingCs dg

-- | creates a Bsdf from a list of Bxdfs and a shading coordinate system
mkBsdf :: [AnyBxdf] -> LocalCoordinates -> Bsdf
mkBsdf bs = Bsdf (V.fromList bs)

data Lambertian = Lambertian {-# UNPACK #-} !Spectrum

instance Bxdf Lambertian where
   bxdfEval (Lambertian r) _ _ = sScale r invPi
   bxdfType _ = mkBxdfType [Reflection, Diffuse]

--
-- The Oren Nayar BxDF
--

data OrenNayar = MkOrenNayar
   Spectrum -- ^ reflectance
   Flt -- ^ the A parameter
   Flt -- ^ the B parameter

mkOrenNayar
   :: Spectrum -- ^ the relfectance
   -> Flt -- ^ the sigma parameter
   -> OrenNayar

mkOrenNayar r sig = MkOrenNayar r a b where
   a = 1 - (sig2 / (2 * (sig2 + 0.33)))
   b = 0.45 * sig2 / (sig2 + 0.09)
   sig2 = sig' * sig'
   sig' = radians sig

instance Bxdf OrenNayar where
   bxdfType _ = mkBxdfType [Reflection, Diffuse]
   
   bxdfEval (MkOrenNayar r a b) wo wi = r' where
      r' = sScale r (invPi * (a + b * maxcos * sina * tanb))
      (sina, tanb)
         | absCosTheta wi > absCosTheta wo = (sinto, sinti / absCosTheta wi)
         | otherwise = (sinti, sinto / absCosTheta wo)
      (sinti, sinto) = (sinTheta wi, sinTheta wo)
      maxcos
         | sinti > 1e-4 && sinto > 1e-4 =
            let
               (sinpi, cospi) = (sinPhi wi, cosPhi wi)
               (sinpo, cospo) = (sinPhi wo, cosPhi wo)
               dcos = cospi * cospo + sinpi * sinpo
            in max 0 dcos
         | otherwise = 0

data Microfacet = Microfacet {
   distribution :: Distribution,
   fresnel :: Fresnel,
   reflectance :: Spectrum
   }

instance Bxdf Microfacet where
   bxdfType _ = mkBxdfType [Reflection, Glossy]
   bxdfEval (Microfacet d fr r) wo wi = sScale (r * fr costh) x where
      x = mfDistD d wh * mfG wo wi wh / (4 * costi * costo)
      costo = abs $ cosTheta wo
      costi = abs $ cosTheta wi
      wh = normalize $ wi + wo
      costh = dot wi wh

   bxdfSample mf wo dirU = bxdfSample' dirU mf wo

   bxdfPdf (Microfacet d _ _) wo wi
      | sameHemisphere wo wi = mfDistPdf d wo wi
      | otherwise = 0

bxdfSample' :: Rand2D -> Microfacet -> Vector -> (Spectrum, Vector, Float)
bxdfSample' dirU mf@(Microfacet d _ _) wo
   | sameHemisphere wo wi = (f, wi, pdf)
   | otherwise = (black, wo, 0)
   where
         f = bxdfEval mf wo wi
         (pdf, wi) = mfDistSample d dirU wo

mfG :: Vector -> Vector -> Vector -> Float
mfG wo wi wh = min 1 $ min (2 * nDotWh * nDotWo / woDotWh) (2 * nDotWh * nDotWi / woDotWh) where
   nDotWh = abs $ cosTheta wh
   nDotWo = abs $ cosTheta wo
   nDotWi = abs $ cosTheta wi
   woDotWh = absDot wo wh

data Distribution
   = Blinn Float

mfDistPdf :: Distribution -> Vector -> Vector -> Float
mfDistPdf (Blinn e) wo wi = (e + 2) * (cost ** e) / (2 * pi * 4 * dot wo h) where
   h@(Vector _ _ hz) = normalize $ wo + wi
   cost = abs hz

mfDistSample :: Distribution -> Rand2D -> Vector -> (Float, Vector)
mfDistSample (Blinn e) (u1, u2) wo = (pdf, wi) where
   pdf = (e + 2) * (cost ** e) / (2 * pi * 4 * dot wo h) -- possible divide by zero?
   wi = (-wo) + (h * vpromote (2 * dot h wo))
   h = toSameHemisphere wo $ sphericalDirection sint cost phi
   cost = u1 ** (1 / (e + 1))
   sint = sqrt $ max 0 (1 - cost * cost)
   phi = u2 * 2 * pi

mfDistD :: Distribution -> Vector -> Float
mfDistD (Blinn e) wh = (e + 2) * invTwoPi * (costh ** e) where
   costh = abs $ cosTheta wh
