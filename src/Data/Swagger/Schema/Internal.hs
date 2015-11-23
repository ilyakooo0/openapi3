{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeSynonymInstances #-}
module Data.Swagger.Schema.Internal where

import Control.Lens
import Data.Aeson
import Data.Monoid
import Data.Proxy
import qualified Data.Text as Text
import GHC.Generics

import Data.Swagger.Internal
import Data.Swagger.Lens

class ToSchema a where
  toSchema :: proxy a -> Schema
  default toSchema :: (Generic a, GToSchema (Rep a)) => proxy a -> Schema
  toSchema = genericToSchema

class GToSchema (f :: * -> *) where
  gtoSchema :: proxy f -> Schema -> Schema

instance {-# OVERLAPPABLE #-} ToSchema a => ToSchema [a] where
  toSchema _ = mempty
    { _schemaType = SchemaArray
    , _schemaItems = Just (SchemaItemsObject (Inline (toSchema (Proxy :: Proxy a))))
    }

instance {-# OVERLAPPING #-} ToSchema String where
  toSchema _ = mempty { _schemaType = SchemaString }

instance ToSchema Bool where
  toSchema _ = mempty { _schemaType = SchemaBoolean }

instance ToSchema Integer where
  toSchema _ = mempty { _schemaType = SchemaInteger }

instance ToSchema Int where toSchema = toSchemaBoundedIntegral

instance ToSchema Double where
  toSchema _ = mempty { _schemaType = SchemaNumber }

toSchemaBoundedIntegral :: forall a proxy. (Bounded a, Integral a) => proxy a -> Schema
toSchemaBoundedIntegral _ = mempty
  & schemaType .~ SchemaInteger
  & schemaMinimum ?~ toInteger (minBound :: a)
  & schemaMaximum ?~ toInteger (maxBound :: a)

toSchemaBoundedEnum :: forall a proxy. (ToJSON a, Bounded a, Enum a) => proxy a -> Schema
toSchemaBoundedEnum _ = mempty
  & schemaType .~ SchemaString
  & schemaEnum ?~ map toJSON [minBound..maxBound :: a]

genericToSchema :: forall a proxy. (Generic a, GToSchema (Rep a)) => proxy a -> Schema
genericToSchema _ = gtoSchema (Proxy :: Proxy (Rep a)) mempty

instance (GToSchema f, GToSchema g) => GToSchema (f :*: g) where
  gtoSchema _ = gtoSchema (Proxy :: Proxy f) <> gtoSchema (Proxy :: Proxy g)

-- | Single constructor data types.
instance GToSchema f => GToSchema (D1 d (C1 c f)) where
  gtoSchema _ = gtoSchema (Proxy :: Proxy f)

-- | Record fields.
instance {-# OVERLAPPABLE #-} (Selector s, GToSchema f) => GToSchema (S1 s f) where
  gtoSchema _ schema = schema
    & schemaProperties . at fieldName ?~ Inline fieldSchema
    & schemaRequired %~ (fieldName :)
    where
      fieldName = Text.pack (selName (undefined :: S1 s f p))
      fieldSchema = gtoSchema (Proxy :: Proxy f) mempty

-- | Optional record fields.
instance {-# OVERLAPPING #-} (Selector s, ToSchema c) => GToSchema (S1 s (K1 i (Maybe c))) where
  gtoSchema _ = schemaProperties . at fieldName ?~ Inline fieldSchema
    where
      fieldName = Text.pack (selName (undefined :: S1 s f p))
      fieldSchema = toSchema (Proxy :: Proxy c)

instance ToSchema c => GToSchema (K1 i c) where
  gtoSchema _ _ = toSchema (Proxy :: Proxy c)

