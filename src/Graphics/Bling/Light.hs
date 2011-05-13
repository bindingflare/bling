
-- | The functions dealing with colours, radiance and light sources
module Graphics.Bling.Light (
   
   -- * Creating Light sources
   Light, mkPointLight, mkDirectional, mkAreaLight, mkSunSky,

   -- * Working with light sources
   LightSample(..), sample, le, lEmit, pdf
   ) where

import Graphics.Bling.Math
import Graphics.Bling.Random
import qualified Graphics.Bling.Shape as S
import Graphics.Bling.Spectrum
import Graphics.Bling.Transform

data LightSample = LightSample {
   de :: Spectrum, -- ^ differential irradiance
   lightSampleWi :: Vector, -- ^ incident direction
   testRay :: Ray, -- ^ for visibility test
   lightSamplePdf :: Float,
   lightSampleDelta :: Bool -- ^ does that light employ a delta-distributuion?
   }

data Light
   = SoftBox ! Int ! Spectrum -- ^ an infinite area light surrounding the whole scene, emitting a constant amount of light from all directions.
   | Directional ! Int !Spectrum !Normal
   | PointLight !Int !Spectrum !Point
   | AreaLight {
      _alId :: Int,
      _alShape :: S.Shape,
      _areaRadiance :: Spectrum,
      _l2w :: Transform, -- ^ the light-to-world transformation
      _w2l :: Transform -- ^ the world-to-light transformation
      }
   | SunSky
      { _ssId :: Int
      , _basis :: LocalCoordinates
      , _tub :: Flt
      }
      -- ^ the Perez sun/sky model

-- two lights are considered equal if the have the same id
instance Eq Light where
   l1 == l2 = (lightId l1) == (lightId l2) where
      lightId (AreaLight lid _ _ _ _) = lid
      lightId (Directional lid _ _) = lid
      lightId (PointLight lid _ _) = lid
      lightId (SoftBox lid _) = lid
      lightId (SunSky lid _ _) = lid
      
-- | creates a directional light source
mkDirectional :: Spectrum -> Normal -> Int -> Light
mkDirectional s n lid = Directional lid s (normalize n)

-- | creates a point light source
mkPointLight
   :: Spectrum -- ^ intensity
   -> Point -- ^ position
   -> Int -- ^ light id
   -> Light
mkPointLight r p lid = PointLight lid r p

-- | creates an area @Light@ sources for a gives shape and spectrum
mkAreaLight
   :: S.Shape -- ^ the @Shape@ to create the area light for
   -> Spectrum -- ^ the emission @Spectrum@
   -> Transform -- ^ the @Transform@ which places the @Light@ in the world
   -> Int -- ^ the light id
   -> Light -- ^ the resulting @Light@
mkAreaLight s r t lid = AreaLight lid s r t (inverse t)

-- | creates the Perez sun/sky model
mkSunSky
   :: Vector -- ^ the up vector
   -> Vector -- ^ the east vector
   -> Flt -- ^ the sky's turbidity
   -> Int -- ^ the light id
   -> Light
mkSunSky up east turb lid = SunSky lid basis turb where
   basis = coordinateSystem' up east

-- | the emission from the surface of an area light source
lEmit :: Light -> Point -> Normal -> Vector -> Spectrum
lEmit (AreaLight _ _ r _ t) _ n' wo'
   | n `dot` wo > 0 = r
   | otherwise = black
   where
      n = transNormal t n'
      wo = transVector t wo'
      
-- all others return black because they are no area light sources
lEmit _ _ _ _ = black

le :: Light -> Ray -> Spectrum
-- area lights must be sampled by intersecting the shape directly and asking
-- that intersection for le
le (AreaLight _ _ _ _ _) _ = black
le (Directional _ _ _) _ = black
le (PointLight _ _ _) _ = black
le (SoftBox _ r) _ = r

-- | samples one light source
sample
   :: Light -- ^ the light to sample
   -> Point -- ^ the point in world space from where the light is viewed
   -> Normal -- ^ the surface normal in world space from where the light is viewed
   -> Rand2D -- ^ the random value for sampling the light
   -> LightSample -- ^ the computed @LightSample@
sample (SoftBox _ r) p n us = lightSampleSB r p n us
sample (Directional _ r d) p n _ = lightSampleD r d p n
sample (PointLight _ r pos) p _ _ = LightSample r' wi ray 1 True where
   r' = sScale r (1 / (sqLen $ pos - p))
   wi = normalize $ pos - p
   ray = segmentRay p pos
sample (AreaLight _ s r l2w w2l) p _ us = LightSample r' wi' ray pd False where
   r' = if ns `dot` (-wi) > 0 then r else black
   p' = transPoint w2l p -- point to be lit in local space
   (ps, ns) = S.sample s p' us -- point in local space
   wi' = transVector l2w wi -- incident vector in world space
   wi = normalize (ps - p') -- incident vector in local space
   pd = S.pdf s p' wi -- pdf (computed in local space)
   ray = transRay l2w (segmentRay ps p') -- vis. test ray (in world space)
   
pdf :: Light -- ^ the light to compute the pdf for
    -> Point -- ^ the point from which the light is viewed
    -> Vector -- ^ the wi vector
    -> Float -- ^ the computed pdf value
pdf (SoftBox _ _) _ _ = undefined
pdf (Directional _ _ _) _ _ = 0 -- zero chance to find the direction by sampling
pdf (AreaLight _ ss _ _ t) p wi = S.pdf ss (transPoint t p) (transVector t wi)
pdf (PointLight _ _ _) _ _ = 0

lightSampleSB :: Spectrum -> Point -> Normal -> Rand2D -> LightSample
lightSampleSB r pos n us = LightSample r (toWorld lDir) (ray $ toWorld lDir) (p lDir) False
   where
      lDir = cosineSampleHemisphere us
      ray dir = Ray pos dir epsilon infinity
      p (Vector _ _ z) = invPi * z
      toWorld = localToWorld (coordinateSystem n)

lightSampleD :: Spectrum -> Normal -> Point -> Normal -> LightSample
lightSampleD r d pos n = LightSample y d ray 1.0 True where
   y = sScale r (absDot n d)
   ray = Ray pos d epsilon infinity

--
-- Perez physically based Sun / Sky model
--

data SunSkyData = SSD
   { sunDir :: Vector
   }

skySpectrum :: SunSkyData -> Vector -> Spectrum
skySpectrum ssd dir
   | dir .! dimZ < 0.001 = black
   | otherwise = fromXYZ x' y' z'
   where
      
      