--
-- HTTP types for use with io-streams and pipes
--
-- Copyright © 2012-2013 Operational Dynamics Consulting, Pty Ltd
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the BSD licence.
--

{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# OPTIONS_HADDOCK hide #-}

module Network.Http.RequestBuilder (
    RequestBuilder,
    RequestBuilderT,
    buildRequest,
    buildRequestPure,
    http,
    setHostname,
    setAccept,
    setAccept',
    setAuthorizationBasic,
    ContentType,
    setContentType,
    setContentLength,
    setExpectContinue,
    setTransferEncoding,
    setHeader
) where

import Blaze.ByteString.Builder (Builder)
import qualified Blaze.ByteString.Builder as Builder (fromByteString,
                                                      toByteString)
import qualified Blaze.ByteString.Builder.Char8 as Builder (fromShow,
                                                            fromString)
import Control.Monad.Identity
import Control.Monad.State
import Data.ByteString (ByteString)
import qualified Data.ByteString.Base64 as BS64
import Data.ByteString.Char8 ()
import qualified Data.ByteString.Char8 as S
import Data.Int (Int64)
import Data.List (intersperse)
import Data.Monoid (mconcat)

import Network.Http.Internal

--
-- | The RequestBuilderT monad allows you to abuse do-notation to
-- conveniently setup a 'Request' object.
-- The type @RequestBuilder@ is aliased to work in the @Identity@ monad.
-- Use @RequestBuilderT@ to operate in any arbitrary monad.
--
type RequestBuilderT m a = StateT Request m a
type RequestBuilder a = RequestBuilderT Identity a

--
-- | Run a RequestBuilder, yielding a Request object you can use on the
-- given connection.
--
-- >     q <- buildRequest $ do
-- >         http POST "/api/v1/messages"
-- >         setContentType "application/json"
-- >         setHostname "clue.example.com" 80
-- >         setAccept "text/html"
-- >         setHeader "X-WhoDoneIt" "The Butler"
--
-- Obviously it's up to you to later actually /send/ JSON data.
--
buildRequest :: Monad m => RequestBuilderT m α -> m Request
buildRequest = flip execStateT defaultRequest

-- | Operates @buildRequest@ in the @Identity@ monad, for building requests
-- purely.
buildRequestPure :: RequestBuilderT Identity a -> Request
buildRequestPure = runIdentity . flip execStateT defaultRequest

-- | A default Request object.
defaultRequest :: Request
defaultRequest = Request {
    qHost = Nothing,
    qMethod = GET,
    qPath = "/",
    qBody = Empty,
    qExpect = Normal,
    qHeaders = emptyHeaders
}

--
-- | Begin constructing a Request, starting with the request line.
--
http :: Monad m => Method -> ByteString -> RequestBuilderT m ()
http m p' = do
    q <- get
    let h1 = qHeaders q
    let h2 = updateHeader h1 "Accept-Encoding" "gzip"

    let e  = case m of
            PUT  -> Chunking
            POST -> Chunking
            _    -> Empty

    let h3 = case e of
            Chunking    -> updateHeader h2 "Transfer-Encoding" "chunked"
            _           -> h2

    put q {
        qMethod = m,
        qPath = p',
        qBody = e,
        qHeaders = h3
    }

--
-- | Set the [virtual] hostname for the request. In ordinary conditions
-- you won't need to call this, as the @Host:@ header is a required
-- header in HTTP 1.1 and is set directly from the name of the server
-- you connected to when calling 'Network.Http.Connection.openConnection'.
--
setHostname :: Monad m => Hostname -> Port -> RequestBuilderT m ()
setHostname h' p = do
    q <- get
    put q {
        qHost = Just v'
    }
  where
    v' :: ByteString
    v' = if p == 80
        then h'
        else Builder.toByteString $ mconcat
           [Builder.fromByteString h',
            Builder.fromString ":",
            Builder.fromShow p]

--
-- | Set a generic header to be sent in the HTTP request. The other
-- methods in the RequestBuilder API are expressed in terms of this
-- function, but we recommend you use them where offered for their
-- stronger types.
--
setHeader :: Monad m => ByteString -> ByteString -> RequestBuilderT m ()
setHeader k' v' = do
    q <- get
    let h0 = qHeaders q
    let h1 = updateHeader h0 k' v'
    put q {
        qHeaders = h1
    }

deleteHeader :: Monad m => ByteString -> RequestBuilderT m ()
deleteHeader k' = do
    q <- get
    let h0 = qHeaders q
    let h1 = removeHeader h0 k'
    put q {
        qHeaders = h1
    }

{-# INLINE setEntityBody #-}
setEntityBody :: Monad m => EntityBody -> RequestBuilderT m ()
setEntityBody e = do
    q <- get
    put q {
        qBody = e
    }

{-# INLINE setExpectMode #-}
setExpectMode :: Monad m => ExpectMode -> RequestBuilderT m ()
setExpectMode e = do
    q <- get
    put q {
        qExpect = e
    }

--
-- | Indicate the content type you are willing to receive in a reply
-- from the server. For more complex @Accept:@ headers, use
-- 'setAccept''.
--
setAccept :: Monad m => ByteString -> RequestBuilderT m ()
setAccept v' = do
    setHeader "Accept" v'

--
-- | Indicate the content types you are willing to receive in a reply
-- from the server in order of preference. A call of the form:
--
-- >         setAccept' [("text/html", 1.0),
-- >                     ("application/xml", 0.8),
-- >                     ("*/*", 0)]
--
-- will result in an @Accept:@ header value of
-- @text\/html; q=1.0, application\/xml; q=0.8, \*\/\*; q=0.0@ as you
-- would expect.
--
setAccept' :: Monad m => [(ByteString,Float)] -> RequestBuilderT m ()
setAccept' tqs = do
    setHeader "Accept" v'
  where
    v' = Builder.toByteString v
    v  = mconcat $ intersperse (Builder.fromString ", ") $ map format tqs

    format :: (ByteString,Float) -> Builder
    format (t',q) =
        mconcat
           [Builder.fromByteString t',
            Builder.fromString "; q=",
            Builder.fromShow q]


--
-- | Set username and password credentials per the HTTP basic
-- authentication method.
--
-- >         setAuthorizationBasic "Aladdin" "open sesame"
--
-- will result in an @Authorization:@ header value of
-- @Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==@.
--
-- Basic authentication does /not/ use a message digest function to
-- encipher the password; the above string is only base-64 encoded and
-- is thus plain-text visible to any observer on the wire and all
-- caches and servers at the other end, making basic authentication
-- completely insecure. A number of web services, however, use SSL to
-- encrypt the connection that then use HTTP basic authentication to
-- validate requests. Keep in mind in these cases the secret is still
-- sent to the servers on the other side and passes in clear through
-- all layers after the SSL termination. Do /not/ use basic
-- authentication to protect secure or user-originated privacy-sensitve
-- information.
--
{-
    This would be better using Builder, right?
-}
setAuthorizationBasic :: Monad m 
                      => ByteString -> ByteString -> RequestBuilderT m ()
setAuthorizationBasic user' passwd' = do
    setHeader "Authorization" v'
  where
    v'   = S.concat ["Basic ", msg']
    msg' = BS64.encode str'
    str' = S.concat [user', ":", passwd']


type ContentType = ByteString


--
-- | Set the MIME type corresponding to the body of the request you are
-- sending. Defaults to @\"text\/plain\"@, so usually you need to set
-- this if 'PUT'ting.
--
setContentType :: Monad m => ContentType -> RequestBuilderT m ()
setContentType v' = do
    setHeader "Content-Type" v'

--
-- | Specify the length of the request body, in bytes.
--
-- RFC 2616 requires that we either send a @Content-Length@ header or
-- use @Transfer-Encoding: chunked@. If you know the exact size ahead
-- of time, then call this function; the body content will still be
-- streamed out by @io-streams@ in more-or-less constant space.
--
-- This function is special: in a PUT or POST request, @http-streams@
-- will assume chunked transfer-encoding /unless/ you specify a content
-- length here, in which case you need to ensure your body function
-- writes precisely that many bytes.
--
--
setContentLength :: Monad m => Int64 -> RequestBuilderT m ()
setContentLength n = do
    deleteHeader "Transfer-Encoding"
    setHeader "Content-Length" (S.pack $ show n)
    setEntityBody $ Static n

--
-- | Override the default setting about how the entity body will be sent.
--
-- This function is special: this explicitly sets the @Transfer-Encoding:@
-- header to @chunked@ and will instruct the library to actually tranfer the
-- body as a stream ("chunked transfer encoding"). See 'setContentLength' for
-- forcing the opposite. You /really/ won't need this in normal operation, but
-- some people are control freaks.
--
setTransferEncoding :: Monad m => RequestBuilderT m ()
setTransferEncoding = do
    deleteHeader "Content-Length"
    setEntityBody Chunking
    setHeader "Transfer-Encoding" "chunked"


--
-- | Specify that this request should set the expectation that the
-- server needs to approve the request before you send it.
--
-- This function is special: in a PUT or POST request, @http-streams@
-- will wait for the server to reply with an HTTP/1.1 100 Continue
-- status before sending the entity body. This is handled internally;
-- you will get the real response (be it successful 2xx, client error,
-- 4xx, or server error 5xx) in 'receiveResponse'. In theory, it
-- should be 417 if the expectation failed.
--
-- Only bother with this if you know the service you're talking to
-- requires clients to send an @Expect: 100-continue@ header and will
-- handle it properly. Most servers don't do any precondition checking,
-- automatically send an intermediate 100 response, and then just read
-- the body regardless, making this a bit of a no-op in most cases.
--
setExpectContinue :: Monad m => RequestBuilderT m ()
setExpectContinue = do
    setHeader "Expect" "100-continue"
    setExpectMode Continue

