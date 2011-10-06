
module Graphics.Bling.IO.RGBE (

   -- * RGBE image format support

   RGBEImage, parseRGBE, rgbeToTextureMap
   
   ) where
   
import Data.List (zipWith4)
import Data.Maybe (isNothing, fromJust)
import qualified Data.Vector.Unboxed as UV
import qualified Data.ByteString.Lazy as BS
import qualified Data.ByteString.Internal as BSI
import Data.Bits ((.&.), (.|.), shiftL)
import Data.Char as C
import Data.Word

import Debug.Trace

import Graphics.Bling.Spectrum
import Graphics.Bling.Texture
import Graphics.Bling.Types

data RGBEImage = RGBE
   { _rgbeSize    :: {-# UNPACK #-} ! PixelSize
   , _rgbePixels  :: ! (UV.Vector Spectrum)
   }

instance Show RGBEImage where
   show (RGBE size px) = "RGBE Image (size=" ++ (show size) ++ (show px) ++ ")"

rgbeToTextureMap :: RGBEImage -> SpectrumMap
rgbeToTextureMap (RGBE size@(w, h) px) = mkTextureMap size eval where
   eval cs = eval' $ unCartesian cs
   eval' (u, v) = px UV.! o where
      o = max 0 $ min (UV.length px - 1) $ y * w + x
      x = floor $ u * fromIntegral w
      y = floor $ v * fromIntegral h
      
type RGBEHeader = (PixelSize)

parseRGBE :: BS.ByteString -> Either String RGBEImage
parseRGBE bs
   | isNothing header = Left "error parsing RGBE header"
   | otherwise = Right $ RGBE (fromJust header) (UV.fromList (concat pixels))
   where
      (rest, header) = parseRGBEHeader bs
      (_, pixels) = parseRGBEPixels rest (fromJust header)

parseRGBEPixels :: BS.ByteString -> PixelSize -> (BS.ByteString, [[Spectrum]])
parseRGBEPixels bs (width, height)
   | width < 8 || width > 0x7fff = readFlatPixels bs (width * height)
   | (r /= 2) || (g /= 2) || ((b .&. 0x80) /= 0) = readFlatPixels bs (width * height)
   | otherwise = readRlePixels bs width height
   where
      (r:g:b:[]) = BS.unpack $ BS.take 3 bs

readRlePixels :: BS.ByteString -> Int -> Int -> (BS.ByteString, [[Spectrum]])
readRlePixels bs width height = go height (bs, []) where
   go 0 x = x
   go n (bs', ls) = go (n-1) (rest, line : ls) where
      (rest, line) = oneLine bs'
   
   oneLine :: BS.ByteString -> (BS.ByteString, [Spectrum])
   oneLine lbs
      | width' /= width = error "invalid scanline width"
      | otherwise = (lrest, zipWith4 rgbeToSpectrum chR chG chB chE)
      where
         width' = shiftL ((fromIntegral b) :: Int) 8 .|. fromIntegral e
         (lbs', chR) = oneChannel $ BS.drop 4 lbs
         (lbs'', chG) = oneChannel lbs'
         (lbs''', chB) = oneChannel lbs''
         (lrest, chE) = oneChannel lbs'''
         (_:_:b:e:_) = BS.unpack $ BS.take 4 lbs

   oneChannel :: BS.ByteString -> (BS.ByteString, [Word8])
   oneChannel cbs = goc width (cbs, []) where
      goc 0 x = x
      goc n (cb, xs)
         | n < 0 = error "ewww"
         | b0 == 0 = error "bad scanline data"
         | b0 > 128 = goc (n - (fromIntegral b0 - 128)) (BS.drop 2 cb, xs ++ Prelude.replicate ((fromIntegral b0) - 128) b1)
         | otherwise = goc (n - fromIntegral b0) (BS.drop (fromIntegral b0 + 1) cb, xs ++ (BS.unpack $ BS.take (fromIntegral b0) cb))
         where
            (b0:b1:_) = BS.unpack $ BS.take 2 cb
   
readFlatPixels :: BS.ByteString -> Int -> (BS.ByteString, [[Spectrum]])
readFlatPixels bs count = trace ("count=" ++ show count++ " len=" ++ show (BS.length bs)) $ go count (bs, []) where
   go 0 x = x
   go n (bs', ss) = go (n-1) (rest, s:ss) where
      (rest, s) = trace ("bs' len = " ++ (show $ BS.length bs')) $ readFlatPixel bs'

readFlatPixel :: BS.ByteString -> (BS.ByteString, [Spectrum])
readFlatPixel bs = (BS.drop 4 bs, [rgbeToSpectrum r g b e]) where
   (r:g:b:e:_) = BS.unpack $ BS.take 4 bs

rgbeToSpectrum :: Word8 -> Word8 -> Word8 -> Word8 -> Spectrum
rgbeToSpectrum r g b e
   | e == 0 = black
   | otherwise = fromRGB (r', g', b')
   where
      r' = fromIntegral r * f;
      g' = fromIntegral g * f;
      b' = fromIntegral b * f;
      f = ldexp 1 ((fromIntegral e :: Int) - (128 + 8))
      ldexp x ex = x * (2 ** fromIntegral ex)

parseRGBEHeader :: BS.ByteString -> (BS.ByteString, Maybe RGBEHeader)
parseRGBEHeader bs = (BS.tail rest, Just size) where
   (_, pixAndSize) = splitHeader bs
   (sizeStr, rest) = BS.span (/=(fromIntegral $ C.ord '\n')) pixAndSize
   size' = BS.split (BSI.c2w ' ') sizeStr
   size = (Prelude.read $ bsToStr (size' !! 3), Prelude.read $ bsToStr (size' !! 1))

bsToStr :: BS.ByteString -> String
bsToStr bs = map BSI.w2c $ BS.unpack bs

splitHeader :: BS.ByteString -> ([BS.ByteString], BS.ByteString)
splitHeader bs = go ([], bs) where
   go (hls, rest)
      | BS.null line = (hls, BS.tail rest)
      | otherwise = go ((line:hls), BS.tail rest')
      where
         (line, rest') = BS.span (/=(BSI.c2w '\n')) rest
   