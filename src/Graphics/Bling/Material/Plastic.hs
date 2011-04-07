
module Graphics.Bling.Material.Plastic (
   -- * Creating Plastic Material
   mkPlastic
   
   ) where

import Graphics.Bling.Texture
import Graphics.Bling.Reflection

mkPlastic
   :: SpectrumTexture
   -> SpectrumTexture
   -> ScalarTexture
   -> Material
   
mkPlastic kd ks kr dg = mkBsdf [diff, spec] sc where
   diff = MkAnyBxdf $ Lambertian rd
   spec = MkAnyBxdf $ Microfacet (Blinn (1 / rough)) (frDiel 1.5 1.0) rs
   rough = kr dg
   rd = kd dg
   rs = ks dg
   sc = shadingCs dg
