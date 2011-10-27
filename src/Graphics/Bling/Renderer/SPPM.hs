
module Graphics.Bling.Renderer.SPPM (

   SPPM, mkSPPM
   
   ) where

import Control.Monad
import Control.Monad.ST
import Data.Bits
import qualified Data.Vector.Mutable as MV
import qualified Data.Vector.Unboxed.Mutable as UMV
import qualified Data.Vector as V
import qualified Text.PrettyPrint as PP

import Graphics.Bling.Camera
import Graphics.Bling.Image
import Graphics.Bling.Light (le)
import Graphics.Bling.Primitive
import qualified Graphics.Bling.Random as R
import Graphics.Bling.Reflection
import Graphics.Bling.Rendering
import Graphics.Bling.Sampling
import Graphics.Bling.Scene
import Graphics.Bling.Spectrum

import Debug.Trace

data SPPM = SPPM Int Flt -- ^ #photons and initial radius

instance Printable SPPM where
   prettyPrint (SPPM _ _) = PP.vcat [
      PP.text "Stochastic Progressive Photon Map" ]

mkSPPM :: Int -> Flt -> SPPM
mkSPPM = SPPM

type Stats = (Flt, Flt) -- (radius², #photons)

lsN :: Stats -> Flt
lsN = snd

lsR2 :: Stats -> Flt
lsR2 = fst

data HitPoint = Hit
   { hpBsdf    :: {-# UNPACK #-} ! Bsdf
   , hpPixel   :: {-# UNPACK #-} ! (Flt, Flt)
   , hpW       :: {-# UNPACK #-} ! Vector
   , hpF       :: {-# UNPACK #-} ! Spectrum
   }

alpha :: Flt
alpha = 0.7

-- | creates a new @HitPoint@ if the provided @Bsdf@ contains non-specular
--   components, or an empty list otherwise
mkHitPoint :: Bsdf -> Vector -> Spectrum -> Sampled s [HitPoint]
mkHitPoint bsdf wo f
   | not (bsdfHasNonSpecular bsdf) = return $! []
   | otherwise = do
      pxpos <- cameraSample >>= \cs -> return (imageX cs, imageY cs)
      return $! [Hit bsdf pxpos wo f]

escaped :: Ray -> Scene -> Spectrum
escaped ray s = V.sum $ V.map (`le` ray) (sceneLights s)

mkHitPoints :: Scene -> MImage s -> R.Rand s [HitPoint]
mkHitPoints scene img = {-# SCC "mkHitPoints" #-}
   liftM concat $ forM (splitWindow $ imageWindow img) $ \w ->
      liftM concat $ sample (mkRandomSampler 1) w 0 0 $ do
         ray <- fireRay $ sceneCam scene
         
         (hps, ls) <- case scene `intersect` ray of
            Just int -> nextV scene int (-(rayDir ray)) white 0 7
            Nothing  -> return $! ([], escaped ray scene)
                           
         (px, py) <- cameraSample >>= \cs -> return (imageX cs, imageY cs)
         liftSampled $ addContrib img (False, ImageSample px py (1, ls))
         return $! hps
   
nextV :: Scene -> Intersection -> Vector -> Spectrum
   -> Int -> Int -> Sampled s ([HitPoint], Spectrum)
nextV s int wo t d md = {-# SCC "nextV" #-} do
   let
      bsdf = intBsdf int
      ls = intLe int wo
   
   -- trace rays for specular reflection and transmission
   (re, lsr) <- cont (d+1) md s bsdf wo (mkBxdfType [Specular, Reflection]) t
   (tr, lst) <- cont (d+1) md s bsdf wo (mkBxdfType [Specular, Transmission]) t
   here <- mkHitPoint bsdf wo t
   seq re $ seq tr $ seq here $ return $! (here ++ re ++ tr, t * (lsr + lst + ls))

cont :: Int -> Int -> Scene -> Bsdf -> Vector -> BxdfType -> Spectrum -> Sampled s ([HitPoint], Spectrum)
cont d md s bsdf wo tp t
   | d == md = return $! ([], black)
   | otherwise =
      let
         (BsdfSample _ pdf f wi) = sampleBsdf' tp bsdf wo 0.5 (0.5, 0.5)
         ray = Ray p wi epsilon infinity
         p = bsdfShadingPoint bsdf
         n = bsdfShadingNormal bsdf
         t' = sScale (f * t) (wi `absDot` n / pdf)
      in if pdf == 0 || isBlack f
         then return $! ([], black)
         else case s `intersect` ray of
            Just int -> nextV s int (-wi) t' d md
            Nothing  -> return $! ([], escaped ray s)

tracePhoton :: Scene -> SpatialHash -> MImage s -> PixelStats s -> Sampled s ()
tracePhoton scene sh img ps = {-# SCC "tracePhoton" #-} do
   ul <- rnd' 0
   ulo <- rnd2D' 0
   uld <- rnd2D' 1
   
   let
      (li, ray, nl, pdf) = sampleLightRay scene ul ulo uld
      wi = -(normalize $ rayDir ray)
      ls = sScale li (absDot nl wi / pdf)
       
   when ((pdf > 0) && not (isBlack li)) $
      nextVertex scene sh wi (scene `intersect` ray) ls 0 img ps


nextVertex :: Scene -> SpatialHash -> Vector ->
   Maybe Intersection -> Spectrum -> Int ->
   MImage s -> PixelStats s -> Sampled s ()

nextVertex _ _ _ Nothing _ _ _ _ = return ()
nextVertex scene sh wi (Just int) li d img ps = {-# SCC "nextVertex" #-} do

   -- add contribution for this photon hit
   let
      bsdf = intBsdf int
      p = bsdfShadingPoint bsdf
      n = bsdfShadingNormal bsdf

   when (bsdfHasNonSpecular bsdf) $ liftSampled $ hashLookup sh p n ps $ \hit -> {-# SCC "contrib" #-} do
      stats <- slup ps hit
      let
         nn = lsN stats
         ratio = (nn + alpha) / (nn + 1)
         r2 = lsR2 stats
         r2' = r2 * ratio
         f = evalBsdf True (hpBsdf hit) (hpW hit) wi
    --     n = bsdfShadingNormal $ hpBsdf hit
         nn' = nn + alpha
         (px, py) = hpPixel hit

      addContrib img (True,
         ImageSample px py (1 / (r2 * pi), hpF hit * f * li))
      sUpdate ps hit (r2', nn')

   -- follow the path
   ubc <- rnd' $ 1 + d * 2
   ubd <- rnd2D' $ 2 + d
   let
      (BsdfSample _ spdf f wo) = sampleAdjBsdf bsdf wi ubc ubd
      pcont = if d > 4 then 0.8 else 1
      li' = sScale (f * li) (absDot wo n / (spdf * pcont))
      ray = Ray p wo epsilon infinity

   unless (spdf == 0 || isBlack li') $
      rnd' (2 + d * 2) >>= \x -> unless (x > pcont) $
         nextVertex scene sh (-wo) (scene `intersect` ray) li' (d+1) img ps

data PixelStats s = PS (UMV.MVector s Stats) SampleWindow

mkPixelStats :: SampleWindow -> Flt -> ST s (PixelStats s)
mkPixelStats wnd r2 = do
   v <- UMV.replicate ((xEnd wnd - xStart wnd + 1) * (yEnd wnd - yStart wnd + 1)) (r2, 0)
   return $! PS v wnd

sIdx :: PixelStats s -> HitPoint -> Int
{-# INLINE sIdx #-}
sIdx (PS _ wnd) hit = w * (iy - yStart wnd) + (ix - xStart wnd) where
   (w, h) = (xEnd wnd - xStart wnd, yEnd wnd - yStart wnd)
   (px, py) = hpPixel hit
   (ix, iy) = (min (w-1) (floor px), min (h-1) (floor py))

slup :: PixelStats s -> HitPoint -> ST s Stats
{-# INLINE slup #-}
slup ps@(PS v _) hit = UMV.read v (sIdx ps hit)

sUpdate :: PixelStats s -> HitPoint -> Stats -> ST s ()
{-# INLINE sUpdate #-}
sUpdate ps@(PS v _) hit = UMV.write v (sIdx ps hit)

data SpatialHash = SH
   { shBounds  :: {-# UNPACK #-} ! AABB
   , shEntries :: ! (V.Vector (V.Vector HitPoint))
   , shScale   :: {-# UNPACK #-} ! Flt -- ^ 1 / bucket size
   }

hash :: (Int, Int, Int) -> Int
{-# INLINE hash #-}
hash (x, y, z) = abs $ (x * 73856093) `xor` (y * 19349663) `xor` (z * 83492791)

hashLookup :: SpatialHash -> Point -> Normal -> PixelStats s -> (HitPoint -> ST s ()) -> ST s ()
hashLookup sh p n ps fun = {-# SCC "hashLookup" #-}
   let
      Vector x y z = abs $ (p - (aabbMin $ shBounds sh)) * vpromote (shScale sh)
      idx = hash (floor x, floor y, floor z) `rem` V.length (shEntries sh)
      hits = V.unsafeIndex (shEntries sh) idx
   in V.forM_ hits $ \hit -> do
      stats <- slup ps hit
      let
         hpn = bsdfShadingNormal $ hpBsdf hit
         v = bsdfShadingPoint (hpBsdf hit) - p
      when (n `dot` hpn > 0 && sqLen v <= lsR2 stats) $ {-# SCC "hlFun" #-} fun hit
      
mkHash :: V.Vector HitPoint -> PixelStats s -> ST s SpatialHash
mkHash hits ps = {-# SCC "mkHash" #-} do
   r2 <- let
            go m hp = slup ps hp >>= \stats -> return $! max (lsR2 stats) m
         in V.foldM' go 0 hits
   
   let
      r = sqrt r2
      cnt = trace ("r_max=" ++ show r) $ V.length hits
      invSize = 1 / (2 * r)
      bounds = V.foldl' go emptyAABB hits where
         go b h = let p = bsdfShadingPoint $ hpBsdf h
                  in extendAABB b $ mkAABB (p - vpromote r) (p + vpromote r)
   
   v' <- MV.replicate cnt []
   V.forM_ hits $ \hp -> do
      stats <- slup ps hp
      let
         r2p = lsR2 stats
         rp = sqrt r2p
         pmin = aabbMin bounds
         
         p = (bsdfShadingPoint $ hpBsdf hp)
         Vector x0 y0 z0 = abs $ (p - vpromote rp - pmin) * vpromote invSize
         Vector x1 y1 z1 = abs $ (p + vpromote rp - pmin) * vpromote invSize
         xs = [floor x0 .. floor x1]
         ys = [floor y0 .. floor y1]
         zs = [floor z0 .. floor z1]
         
      unless (r2p == 0) $ forM_ [(x, y, z) | x <- xs, y <- ys, z <- zs] $ \pos -> -- trace (show pos) $
         let idx = hash pos `rem` cnt
         in MV.read v' idx >>= \old -> MV.write v' idx (hp : old)

   -- convert to an array of arrays
   v <- V.generateM (MV.length v') $ \i -> fmap V.fromList (MV.read v' i)

   return $ SH bounds v invSize

instance Renderer SPPM where
   render (SPPM n' r) job report = {-# SCC "render" #-} do
      
      let
         scene = jobScene job
         w = SampleWindow 0 0 0 0 -- just a hack, should split off camera sample generation
         d = 3 -- sample depth
         n1d = 2 * d + 1
         n2d = d + 2
         sn = max 1 $ ceiling $ sqrt (fromIntegral n' :: Float)
         n = sn * sn

      img <- stToIO $ thaw $ mkJobImage job
      pxStats <- stToIO $ mkPixelStats (imageWindow img) (r*r)
      
      forM_ [1..] $ \passNum -> do
         seed <- R.ioSeed
         hitPoints <- liftM V.fromList $ stToIO $ R.runWithSeed seed $ mkHitPoints scene img
         hitMap <- stToIO $ mkHash hitPoints pxStats
         pseed <- R.ioSeed
         _ <- stToIO $ R.runWithSeed pseed $
            sample (mkStratifiedSampler sn sn) w n1d n2d $ tracePhoton scene hitMap img pxStats
         
         img' <- stToIO $ freeze img
         _ <- report $ PassDone passNum img' (1 / fromIntegral (passNum * n))
         return ()
         
      return ()