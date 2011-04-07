
module Graphics.Bling.Plastic where

import Graphics.Bling.Material
import Graphics.Bling.Math
import Graphics.Bling.Microfacet
import Graphics.Bling.Specular
import Graphics.Bling.Texture
import Graphics.Bling.Transport

plasticMaterial :: SpectrumTexture -> SpectrumTexture -> Float -> Material
plasticMaterial kd ks rough dg = mkBsdf [diff, spec] sc where
   diff = MkAnyBxdf $ Lambertian rd
   spec = MkAnyBxdf $ Microfacet (Blinn (1 / rough)) (frDiel 1.0 1.5) rs
   rd = kd dg
   rs = ks dg
   sc = shadingCs dg
   