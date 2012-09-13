
module Graphics.Bling.Fresnel (

   -- * Fresnel incidence effects
   
   Fresnel, frDielectric, frConductor, frNoOp, frApproxEta, frApproxK
   
   ) where

import Graphics.Bling.Math   
import Graphics.Bling.Spectrum

type Fresnel = Float -> Spectrum

-- | a no-op Fresnel implementation, which always returns white
--   @Spectrum@
frNoOp :: Fresnel
frNoOp = const white

-- | Fresnel incidence effects for dielectrics
frDielectric :: Float -> Float -> Fresnel
frDielectric etai etat cosi
   | sint >= 1 = white -- total internal reflection
   | otherwise = frDiel' (abs cosi') cost (sConst ei) (sConst et)
   where
      cosi' = clamp cosi (-1) 1
      (ei, et) = if cosi' > 0 then (etai, etat) else (etat, etai)
      -- find sint using Snell's law
      sint = (ei / et) * sqrt (max 0 (1 - cosi' * cosi'))
      cost = sqrt $ max 0 (1 - sint * sint)
      
frDiel' :: Float -> Float -> Spectrum -> Spectrum -> Spectrum
frDiel' cosi cost etai etat = sScale (rPar * rPar + rPer * rPer) 0.5 where
   rPar = (sScale etat cosi - sScale etai cost) /
          (sScale etat cosi + sScale etai cost)
   rPer = (sScale etai cosi - sScale etat cost) /
          (sScale etai cosi + sScale etat cost)

-- | Fresnel incidence effects for conductors
frConductor
   :: Spectrum -- ^ eta
   -> Spectrum -- ^ k
   -> Fresnel
frConductor eta k cosi = (rPer2 + rPar2) / 2 where
   rPer2 = (tmpF - ec2 + sConst (acosi * acosi)) /
           (tmpF + ec2 + sConst (acosi * acosi))
   rPar2 = (tmp - ec2 + white) /
           (tmp + ec2 + white)
   ec2 = sScale eta (2 * acosi)
   tmp = sScale (eta * eta + k * k) (acosi * acosi)
   tmpF = eta * eta + k * k
   acosi = abs cosi

frApproxEta :: Spectrum -> Spectrum
frApproxEta r = (white + r') / (white - r') where
   r' = sqrt $ sClamp 0 0.999 r

frApproxK :: Spectrum -> Spectrum
frApproxK r = sScale (sqrt $ refl / (white - refl)) 2 where
   refl = sClamp 0 0.999 r

