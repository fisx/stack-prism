{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE RankNTypes #-}

module Data.Iso.Generic (mkIsoList, IsoList(..), IsoLhs) where

import Data.Iso
import GHC.Generics


-- | Derive a list of partial isomorphisms, one for each constructor in the 'Generic' datatype @a@. The list is wrapped in the unary constructor @IsoList@. Within that constructor, the isomorphisms are separated by the right-associative binary infix constructor @:&@. Finally, the individual isomorphisms are wrapped in the unary constructor @I@. These constructors are all exported by this module, but no documentation is generated for them by Hackage.
--
-- As an example, here is how to define the isomorphisms @nil@ and @cons@ for @[a]@, which is an instance of @Generic@:
--
-- > nil  :: Iso              t  ([a] :- t)
-- > cons :: Iso (a :- [a] :- t) ([a] :- t)
-- > (nil, cons) = (nil', cons')
-- >   where
-- >     IsoList (I nil' :& I cons') = mkIsoList
--
-- Currently GHC requires the extra indirection through @nil'@ and @cons'@, possibly due to a bug. If this is fixed, the example above can be written in a more direct way:
--
-- > nil  :: Iso              t  ([a] :- t)
-- > cons :: Iso (a :- [a] :- t) ([a] :- t)
-- > IsoList (I nil :& I cons) = mkIsoList
--
-- If you are familiar with the generic representations from @Data.Generic@, you might be interested in the exact types of the various constructors in which the isomorphisms are wrapped:
--
-- > I       :: (forall t. Iso (IsoLhs f t) (a :- t)) -> IsoList (M1 C c f) a
-- > (:&)    :: IsoList f a -> IsoList g a -> IsoList (f :+: g) a
-- > IsoList :: IsoList f a -> IsoList (M1 D c f) a
--
-- The type constructor @IsoLhs@ that appears in the type of @I@ is an internal type family that builds the proper heterogenous list of types (using ':-') based on the constructor's fields.
mkIsoList :: (Generic a, MkIsoList (Rep a)) => IsoList (Rep a) a
mkIsoList = mkIsoList' to (Just . from)


class MkIsoList (f :: * -> *) where
  data IsoList (f :: * -> *) (a :: *)
  mkIsoList' :: (f p -> a) -> (a -> Maybe (f q)) -> IsoList f a


instance MkIsoList f => MkIsoList (M1 D c f) where
  data IsoList (M1 D c f) a = IsoList (IsoList f a)
  mkIsoList' f' g' = IsoList (mkIsoList' (f' . M1) (fmap unM1 . g'))


infixr :&

instance (MkIsoList f, MkIsoList g) => MkIsoList (f :+: g) where
  data IsoList (f :+: g) a = IsoList f a :& IsoList g a
  mkIsoList' f' g' = f f' g' :& g f' g'
    where
      f :: forall a p q. ((f :+: g) p -> a) -> (a -> Maybe ((f :+: g) q)) -> IsoList f a
      f _f' _g' = mkIsoList' (\fp -> _f' (L1 fp)) (matchL _g')
      g :: forall a p q. ((f :+: g) p -> a) -> (a -> Maybe ((f :+: g) q)) -> IsoList g a
      g _f' _g' = mkIsoList' (\gp -> _f' (R1 gp)) (matchR _g')

      matchL :: (a -> Maybe ((f :+: g) q)) -> a -> Maybe (f q)
      matchL _g' a = case _g' a of
        Just (L1 f) -> Just f
        _ -> Nothing

      matchR :: (a -> Maybe ((f :+: g) q)) -> a -> Maybe (g q)
      matchR _g' a = case _g' a of
        Just (R1 g) -> Just g
        _ -> Nothing


instance MkIso f => MkIsoList (M1 C c f) where

  data IsoList (M1 C c f) a = I (forall t cat. FromIso cat => cat (IsoLhs f t) (a :- t))

  mkIsoList' f' g' = I (fromIso (Iso (f f') (g g')))
    where
      f :: forall a p t. (M1 C c f p -> a) -> IsoLhs f t -> a :- t
      f _f' lhs = mapHead (_f' . M1) (mkR lhs)
      g :: forall a p t. (a -> Maybe (M1 C c f p)) -> (a :- t) -> Maybe (IsoLhs f t)
      g _g' (a :- t) = fmap (mkL . (:- t) . unM1) (_g' a)


-- Deriving types and conversions for single constructors

class MkIso (f :: * -> *) where
  type IsoLhs (f :: * -> *) (t :: *) :: *
  mkR :: forall p t. IsoLhs f t -> (f p :- t)
  mkL :: forall p t. (f p :- t) -> IsoLhs f t

instance MkIso U1 where
  type IsoLhs U1 t = t
  mkR t         = U1 :- t
  mkL (U1 :- t) = t

instance MkIso (K1 i a) where
  type IsoLhs (K1 i a) t = a :- t
  mkR (h :- t) = K1 h :- t
  mkL (K1 h :- t) = h :- t

instance MkIso f => MkIso (M1 i c f) where
  type IsoLhs (M1 i c f) t = IsoLhs f t
  mkR = mapHead M1 . mkR
  mkL = mkL . mapHead unM1

instance (MkIso f, MkIso g) => MkIso (f :*: g) where
  type IsoLhs (f :*: g) t = IsoLhs f (IsoLhs g t)
  mkR t = (hf :*: hg) :- tg
    where
      hf :- tf = mkR t
      hg :- tg = mkR tf
  mkL ((hf :*: hg) :- t) = mkL (hf :- mkL (hg :- t))



mapHead :: (a -> b) -> (a :- t) -> (b :- t)
mapHead f (h :- t) = f h :- t
