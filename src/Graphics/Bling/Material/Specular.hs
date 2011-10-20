
module Graphics.Bling.Material.Specular (
   
   -- * Specular materials
   
   glassMaterial, mirrorMaterial,

   -- * Specular BxDFs
   
   SpecularReflection, SpecularTransmission,
   mkSpecRefl
   
   ) where

import Graphics.Bling.Math
import Graphics.Bling.Reflection
import Graphics.Bling.Spectrum
import Graphics.Bling.Texture

import Debug.Trace

-- | a glass material
glassMaterial
   :: ScalarTexture -- ^ index of refraction
   -> SpectrumTexture -- ^ reflection color
   -> SpectrumTexture -- ^ transmission color
   -> Material
glassMaterial iort rt tt dgg dgs = mkBsdf' [refl, trans] dgg dgs where
   refl = MkAnyBxdf $ mkSpecRefl r $ frDielectric 1 ior
   trans = MkAnyBxdf $ SpecularTransmission t 1 ior
   r = sClamp' $ rt dgs
   t = sClamp' $ tt dgs
   ior = iort dgs
   
mirrorMaterial
   :: SpectrumTexture -- ^ reflection color
   -> Material
mirrorMaterial rt dgg dgs = mkBsdf' [bxdf] dgg dgs where
   bxdf = MkAnyBxdf $ SpecularReflection r frNoOp
   r = sClamp 0 1 $ rt dgs

data SpecularTransmission = SpecularTransmission {
   _specTransT    :: {-# UNPACK #-} ! Spectrum,
   _specTransEi   :: {-# UNPACK #-} ! Flt,
   _specTransEt   :: {-# UNPACK #-} ! Flt
   }

instance Bxdf SpecularTransmission where
   bxdfType _ = mkBxdfType [Transmission, Specular]
   bxdfEval _ _ _ = black
   bxdfPdf _ _ _ = 0
   bxdfSample (SpecularTransmission t ei' et') wo@(Vector wox woy _) _
      | sint2 >= 1 = (black, wo, 0) -- total internal reflection
      | isNaN eta = error "nan eta"
      | isNaN cost' = error "nan cost'"
      | sNaN f = error "nan f"
      | otherwise = (f, wi, 1)
      where
         -- find out which eta is incident / transmitted
         entering = cosTheta wo > 0
         (ei, et) = if entering then (ei', et') else (et', ei')

         -- find transmitted ray direction
         sini2 = sinTheta2 wo
         eta = ei / et
         sint2 = eta * eta * sini2
         cost' = sqrt $ max 0 (1 - sint2)
         cost = if entering then (-cost') else cost'
         wi = Vector (eta * (-wox)) (eta * (-woy)) cost
         f' = frDielectric ei' et' $ cosTheta wo
         f =  (white - f') * sScale t (1 / absCosTheta wi)

data SpecularReflection = SpecularReflection {
   _specReflR        :: {-# UNPACK #-} ! Spectrum,
   _specReflFresnel  :: ! Fresnel
   }

mkSpecRefl
   :: Spectrum 
   -> Fresnel
   -> SpecularReflection
   
mkSpecRefl = SpecularReflection

instance Bxdf SpecularReflection where
   bxdfType _ = mkBxdfType [Reflection, Specular]
   bxdfEval _ _ _ = black
   bxdfPdf _ _ _ = 0
   bxdfSample (SpecularReflection r fr) wo@(Vector x y z) _ = (f, wi, 1) where
      wi = Vector (-x) (-y) z
      f = sScale (r * fr (cosTheta wo)) (1 / absCosTheta wi)
