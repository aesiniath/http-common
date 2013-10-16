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

{-# LANGUAGE OverloadedStrings  #-}
{-# OPTIONS_HADDOCK not-home #-}

--
-- | Basic types used in HTTP communications. This modules is re-exported by
-- both "Network.Http.Client" and "Pipes.Http.Client", so if you're using
-- either of those you don't need to explicitly import this module.
--

module Network.Http.Types (
    Hostname,
    Port,
    Request,
    EntityBody(..),
    ExpectMode(..),
    Response,
    StatusCode,
    TransferEncoding(..),
    ContentEncoding(..),
    getStatusCode,
    getStatusMessage,
    getHeader,
    Method(..),
    Headers,
    emptyHeaders,
    updateHeader,
    removeHeader,
    buildHeaders,
    lookupHeader,
    retreiveHeaders,
    HttpParseException(..),

    -- 
    RequestBuilder,
    buildRequest,
    http,
    setHostname,
    setAccept,
    setAccept',
    setAuthorizationBasic,
    ContentType,
    setContentType,
    setContentLength,
    setExpectContinue,
    setHeader

) where

import Network.Http.Internal
import Network.Http.RequestBuilder
