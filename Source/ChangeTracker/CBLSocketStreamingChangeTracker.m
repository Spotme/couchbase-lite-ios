//
//  CBLSocketChangeTracker.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
// <http://wiki.apache.org/couchdb/HTTP_database_API#Changes>

#import "CBLSocketStreamingChangeTracker.h"
#import "CBLRemoteRequest.h"
#import "CBLAuthorizer.h"
#import "CBLStatus.h"
#import "CBLBase64.h"
#import "MYBlockUtils.h"
#import "MYURLUtils.h"
#import "CBL_Replicator.h"
#import <string.h>
#import "CBLJSONReader.h"


#define kReadLength 4096u

typedef void (^CBLChangeMatcherClient)(id sequence, NSString* docID, NSArray* revs, bool deleted, bool removed);

@interface CBLChangeMatcher : CBLJSONDictMatcher
+ (CBLJSONMatcher*) changesFeedMatcherWithClient: (CBLChangeMatcherClient)client;
@end


@implementation CBLSocketStreamingChangeTracker


- (BOOL) start {
    if (_trackingInput)
        return NO;

    LogTo(ChangeTracker, @"%@: Starting...", self);
    [super start];
    
    __weak CBLSocketStreamingChangeTracker* weakSelf = self;
    CBLJSONMatcher* root = [CBLChangeMatcher changesFeedMatcherWithClient:
                            ^(id sequence, NSString *docID, NSArray *revs, bool deleted, bool removed) {
                                // Callback when the parser reads another change from the feed:
                                CBLSocketStreamingChangeTracker* strongSelf = weakSelf;
                                strongSelf.lastSequenceID = sequence;
                                [strongSelf.client changeTrackerReceivedSequence: sequence
                                                                           docID: docID
                                                                          revIDs: revs
                                                                         deleted: deleted
                                                                         removed: removed];
                            }];
    _parser = [[CBLJSONReader alloc] initWithMatcher: root];
    
    NSURL* url = self.changesFeedURL;
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(NULL, CFSTR("GET"),
                                                          (__bridge CFURLRef)url,
                                                          kCFHTTPVersion1_1);
    Assert(request);
    
    // Add headers from my .requestHeaders property:
    [self.requestHeaders enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        CFHTTPMessageSetHeaderFieldValue(request, (__bridge CFStringRef)key, (__bridge CFStringRef)value);
    }];

    // Add cookie headers from the NSHTTPCookieStorage:
    NSArray* cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL: url];
    NSDictionary* cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies: cookies];
    for (NSString* headerName in cookieHeaders) {
        CFHTTPMessageSetHeaderFieldValue(request,
                                         (__bridge CFStringRef)headerName,
                                         (__bridge CFStringRef)cookieHeaders[headerName]);
    }

    // If this is a retry, set auth headers from the credential we got:
    if (_unauthResponse && _credential) {
        NSString* password = _credential.password;
        if (!password) {
            // For some reason the password sometimes isn't accessible, even though we checked
            // .hasPassword when setting _credential earlier. (See #195.) Keychain bug??
            // If this happens, try looking up the credential again:
            LogTo(ChangeTracker, @"Huh, couldn't get password of %@; trying again", _credential);
            _credential = [self credentialForAuthHeader:
                                                [self authHeaderForResponse: _unauthResponse]];
            password = _credential.password;
        }
        if (password) {
            CFIndex unauthStatus = CFHTTPMessageGetResponseStatusCode(_unauthResponse);
            Assert(CFHTTPMessageAddAuthentication(request, _unauthResponse,
                                                  (__bridge CFStringRef)_credential.user,
                                                  (__bridge CFStringRef)password,
                                                  kCFHTTPAuthenticationSchemeBasic,
                                                  unauthStatus == 407));
        } else {
            Warn(@"%@: Unable to get password of credential %@", self, _credential);
            _credential = nil;
            CFRelease(_unauthResponse);
            _unauthResponse = NULL;
        }
    } else if (_authorizer) {
        NSString* authHeader = [_authorizer authorizeHTTPMessage: request forRealm: nil];
        if (authHeader)
            CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Authorization"),
                                             (__bridge CFStringRef)(authHeader));
    }

    // Now open the connection:
    LogTo(SyncVerbose, @"%@: GET %@", self, url.resourceSpecifier);
    CFReadStreamRef cfInputStream = CFReadStreamCreateForHTTPRequest(NULL, request);
    CFRelease(request);
    if (!cfInputStream)
        return NO;
    
    CFReadStreamSetProperty(cfInputStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);

    // Configure HTTP proxy -- CFNetwork makes us do this manually, unlike NSURLConnection :-p
    CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
    if (proxySettings) {
        CFArrayRef proxies = CFNetworkCopyProxiesForURL((__bridge CFURLRef)url, proxySettings);
        if (proxies) {
            if (CFArrayGetCount(proxies) > 0) {
                CFTypeRef proxy = CFArrayGetValueAtIndex(proxies, 0);
                LogTo(ChangeTracker, @"Changes feed using proxy %@", proxy);
                bool ok = CFReadStreamSetProperty(cfInputStream, kCFStreamPropertyHTTPProxy, proxy);
                Assert(ok);
            }
            CFRelease(proxies);
        }
        CFRelease(proxySettings);
    }

    if (_databaseURL.my_isHTTPS) {
        // Enable SSL for this connection.
        // Disable TLS 1.2 support because it breaks compatibility with some SSL servers;
        // workaround taken from Apple technote TN2287:
        // http://developer.apple.com/library/ios/#technotes/tn2287/
        NSDictionary *settings = $dict({(id)kCFStreamSSLLevel,
                                        @"kCFStreamSocketSecurityLevelTLSv1_0SSLv3"},
                                       {(id)kCFStreamSSLValidatesCertificateChain, @NO});
        CFReadStreamSetProperty(cfInputStream,
                                kCFStreamPropertySSLSettings, (CFTypeRef)settings);
    }
    
    _gotResponseHeaders = _atEOF = _inputAvailable = false;
    
    _inputBuffer = [[NSMutableData alloc] initWithCapacity: kReadLength];
    
    _trackingInput = (NSInputStream*)CFBridgingRelease(cfInputStream);
    [_trackingInput setDelegate: self];
    [_trackingInput scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    [_trackingInput open];
    _startTime = CFAbsoluteTimeGetCurrent();
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, self.changesFeedURL);
    return YES;
}


- (void) clearConnection {
    [_trackingInput close];
    [_trackingInput removeFromRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    _trackingInput = nil;
    _inputBuffer = nil;
    _changeBuffer = nil;
    _inputAvailable = false;
}


- (void) stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(start)
                                               object: nil];    // cancel pending retries
    if (_trackingInput) {
        LogTo(ChangeTracker, @"%@: stop", self);
        [self clearConnection];
    }
    _parser = nil;
    [super stop];
}


- (void)dealloc
{
    if (_unauthResponse) CFRelease(_unauthResponse);
}


#pragma mark - SSL & AUTHORIZATION:


- (BOOL) checkSSLCert {
    SecTrustRef sslTrust = (SecTrustRef) CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                                  kCFStreamPropertySSLPeerTrust);
    if (sslTrust) {
        NSURL* url = CFBridgingRelease(CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                                kCFStreamPropertyHTTPFinalURL));
        BOOL trusted = [_client changeTrackerApproveSSLTrust: sslTrust
                                                     forHost: url.host
                                                        port: (UInt16)url.port.intValue];
        CFRelease(sslTrust);
        if (!trusted) {
            //TODO: This error could be made more precise
            [self failedWithError: [NSError errorWithDomain: NSURLErrorDomain
                                                       code: NSURLErrorServerCertificateUntrusted
                                                   userInfo: nil]];
            return NO;
        }
    }
    return YES;
}


- (NSString*) authHeaderForResponse: (CFHTTPMessageRef)response {
    return CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(response,
                                                               CFSTR("WWW-Authenticate")));
}


- (NSURLCredential*) credentialForAuthHeader: (NSString*)authHeader {
    NSString* realm;
    NSString* authenticationMethod;
    
    // Basic & digest auth: http://www.ietf.org/rfc/rfc2617.txt
    if (!authHeader)
        return nil;

    // Get the auth type:
    if ([authHeader hasPrefix: @"Basic"])
        authenticationMethod = NSURLAuthenticationMethodHTTPBasic;
    else if ([authHeader hasPrefix: @"Digest"])
        authenticationMethod = NSURLAuthenticationMethodHTTPDigest;
    else
        return nil;
    
    // Get the realm:
    NSRange r = [authHeader rangeOfString: @"realm=\""];
    if (r.length == 0)
        return nil;
    NSUInteger start = NSMaxRange(r);
    r = [authHeader rangeOfString: @"\"" options: 0
                            range: NSMakeRange(start, authHeader.length - start)];
    if (r.length == 0)
        return nil;
    realm = [authHeader substringWithRange: NSMakeRange(start, r.location - start)];
    
    NSURLCredential* cred;
    cred = [_databaseURL my_credentialForRealm: realm authenticationMethod: authenticationMethod];
    if (!cred.hasPassword)
        cred = nil;     // TODO: Add support for client certs
    return cred;
}


- (BOOL) readResponseHeader {
    CFHTTPMessageRef response;
    response = (CFHTTPMessageRef) CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                           kCFStreamPropertyHTTPResponseHeader);
    Assert(response);
    _gotResponseHeaders = true;
    NSDictionary* errorInfo = nil;

    // Handle authentication failure (401 or 407 status):
    CFIndex status = CFHTTPMessageGetResponseStatusCode(response);
    LogTo(ChangeTracker, @"%@ got status %ld", self, status);
    if (status == 401 || status == 407) {
        NSString* authorization = [_requestHeaders objectForKey: @"Authorization"];
        NSString* authResponse = [self authHeaderForResponse: response];
        if (!_credential && !authorization) {
            _credential = [self credentialForAuthHeader: authResponse];
            LogTo(ChangeTracker, @"%@: Auth challenge; credential = %@", self, _credential);
            if (_credential) {
                // Recoverable auth failure -- close socket but try again with _credential:
                _unauthResponse = response;
                [self clearConnection];
                [self retry];
                return NO;
            }
        }
        LogTo(ChangeTracker, @"%@: HTTP auth failed; sent Authorization: %@  ;  got WWW-Authenticate: %@",
            self, authorization, authResponse);
        errorInfo = $dict({@"HTTPAuthorization", authorization},
                          {@"HTTPAuthenticateHeader", authResponse});
    }

    CFRelease(response);
    if (status >= 300) {
        self.error = CBLStatusToNSErrorWithInfo((CBLStatus)status, self.changesFeedURL, errorInfo);
        [self stop];
        return NO;
    }
    _retryCount = 0;
    return YES;
}


#pragma mark - STREAM HANDLING:


- (void) readFromInput {
    Assert(_inputAvailable);
    _inputAvailable = false;
    
    uint8_t buffer[kReadLength];
    NSInteger bytesRead = [_trackingInput read: buffer maxLength: sizeof(buffer)];
    if (bytesRead > 0)
        [self parseBytes: buffer length: bytesRead];
}


- (void) handleEOF {
    _atEOF = true;
    if (!_gotResponseHeaders || (_mode == kContinuous && _inputBuffer.length > 0)) {
        [self failedWithError: [NSError errorWithDomain: NSURLErrorDomain
                                                   code: NSURLErrorNetworkConnectionLost
                                               userInfo: nil]];
        return;
    }
    if (_mode == kContinuous) {
        [self stop];
    } else if ([self endParsingData]) {
        // Successfully reached end.
        [_client changeTrackerFinished];
        [self clearConnection];
        if (_continuous) {
            if (_mode == kOneShot && _pollInterval == 0.0)
                _mode = kLongPoll;
            if (_pollInterval > 0.0)
                LogTo(ChangeTracker, @"%@: Next poll of _changes feed in %g sec...",
                      self, _pollInterval);
            [self retryAfterDelay: _pollInterval];       // Next poll...
        } else {
            [self stopped];
        }
    } else {
        // JSON must have been truncated, probably due to socket being closed early.
        if (_mode == kOneShot) {
            [self failedWithError: [NSError errorWithDomain: NSURLErrorDomain
                                                       code: NSURLErrorNetworkConnectionLost
                                                   userInfo: nil]];
            return;
        }
        NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _startTime;
        Warn(@"%@: Longpoll connection closed (by proxy?) after %.1f sec", self, elapsed);
        if (elapsed >= 30.0) {
            // Looks like the connection got closed by a proxy (like AWS' load balancer) while the
            // server was waiting for a change to send, due to lack of activity.
            // Lower the heartbeat time to work around this, and reconnect:
            self.heartbeat = MIN(_heartbeat, elapsed * 0.75);
            [self clearConnection];
            [self start];       // Next poll...
        } else {
            // Response data was truncated. This has been reported as an intermittent error
            // (see TouchDB issue #241). Treat it as if it were a socket error -- i.e. pause/retry.
            [self failedWithError: [NSError errorWithDomain: NSURLErrorDomain
                                                       code: NSURLErrorNetworkConnectionLost
                                                   userInfo: nil]];
        }
    }
}


- (void) failedWithError:(NSError*) error {
    // Map lower-level errors from CFStream to higher-level NSURLError ones:
    if ($equal(error.domain, NSPOSIXErrorDomain)) {
        if (error.code == ECONNREFUSED)
            error = [NSError errorWithDomain: NSURLErrorDomain
                                        code: NSURLErrorCannotConnectToHost
                                    userInfo: error.userInfo];
    }
    [self clearConnection];
    [super failedWithError: error];
}


- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)eventCode {
    __unused id keepMeAround = self; // retain myself so I can't be dealloced during this method
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable: {
            LogTo(ChangeTracker, @"%@: HasBytesAvailable %@", self, stream);
            if (!_gotResponseHeaders) {
                if (![self checkSSLCert] || ![self readResponseHeader])
                    return;
            }
            _inputAvailable = true;
            [self readFromInput];
            break;
        }
            
        case NSStreamEventEndEncountered:
            LogTo(ChangeTracker, @"%@: EndEncountered %@", self, stream);
            [self handleEOF];
            break;
            
        case NSStreamEventErrorOccurred:
            [self failedWithError: stream.streamError];
            break;
            
        default:
            LogTo(ChangeTracker, @"%@: Event %lx on %@", self, (long)eventCode, stream);
            break;
    }
}

- (BOOL) parseBytes: (const void*)bytes length: (size_t)length {
    LogTo(ChangeTracker, @"%@: read %ld bytes", self, (long)length);
    if (![_parser parseBytes: bytes length: length]) {
        Warn(@"JSON error parsing _changes feed: %@", _parser.errorString);
        [self failedWithError: [NSError errorWithDomain: @"CBLChangeTracker"
                                                   code: kCBLStatusBadChangesFeed userInfo: nil]];
        return NO;
    }
    return YES;
}

- (BOOL) endParsingData {
    if (![_parser finish]) {
        Warn(@"Truncated changes feed");
        return NO;
    }
    return YES;
}

@end

#pragma mark - PARSER


@interface CBLRevInfoMatcher : CBLJSONDictMatcher
@end

@implementation CBLRevInfoMatcher
{
    NSMutableArray* _revIDs;
}

- (id)initWithArray: (NSMutableArray*)revIDs
{
    self = [super init];
    if (self) {
        _revIDs = revIDs;
    }
    return self;
}

- (bool) matchValue:(id)value forKey:(NSString *)key {
    if ([key isEqualToString: @"rev"])
        [_revIDs addObject: value];
    return true;
}

@end



@implementation CBLChangeMatcher
{
    id _sequence;
    NSString* _docID;
    NSMutableArray* _revs;
    bool _deleted;
    bool _removed;
    CBLTemplateMatcher* _revsMatcher;
    CBLChangeMatcherClient _client;
}

+ (CBLJSONMatcher*) changesFeedMatcherWithClient: (CBLChangeMatcherClient)client {
    CBLChangeMatcher* changeMatcher = [[CBLChangeMatcher alloc] initWithClient: client];
    id template = @[ @{@"results": @[changeMatcher]} ];
    return [[CBLTemplateMatcher alloc] initWithTemplate: template];
}

- (id) initWithClient: (CBLChangeMatcherClient)client {
    self = [super init];
    if (self) {
        _client = client;
        _revs = $marray();
        CBLRevInfoMatcher* m = [[CBLRevInfoMatcher alloc] initWithArray: _revs];
        _revsMatcher = [[CBLTemplateMatcher alloc] initWithTemplate: @[m]];
    }
    return self;
}

- (bool) matchValue:(id)value forKey:(NSString *)key {
    if ([key isEqualToString: @"deleted"])
        _deleted = [value boolValue];
    if ([key isEqualToString: @"removed"])
        _removed = [value boolValue];
    else if ([key isEqualToString: @"seq"])
        _sequence = value;
    else if ([self.key isEqualToString: @"id"])
        _docID = value;
    return true;
}

- (CBLJSONArrayMatcher*) startArray {
    if ([self.key isEqualToString: @"changes"])
        return (CBLJSONArrayMatcher*)_revsMatcher;
    return [super startArray];
}

- (id) end {
    //Log(@"Ended ChangeMatcher with seq=%@, id='%@', deleted=%d, revs=%@", _sequence, _docID, _deleted, _revs);
    if (!_sequence || !_docID || _revs.count == 0)
        return nil;
    _client(_sequence, _docID, [_revs copy], _deleted, _removed);
    _sequence = nil;
    _docID = nil;
    _deleted = false;
    [_revs removeAllObjects];
    return self;
}

@end


TestCase(CBLChangeMatcher) {
    NSString* kJSON = @"{\"results\":[\
    {\"seq\":1,\"id\":\"1\",\"changes\":[{\"rev\":\"2-751ac4eebdc2a3a4044723eaeb0fc6bd\"}],\"deleted\":true},\
    {\"seq\":2,\"id\":\"10\",\"changes\":[{\"rev\":\"2-566bffd5785eb2d7a79be8080b1dbabb\"}],\"deleted\":true},\
    {\"seq\":3,\"id\":\"100\",\"changes\":[{\"rev\":\"2-ec2e4d1833099b8a131388b628fbefbf\"}],\"deleted\":true}]}";
    NSMutableArray* docIDs = $marray();
    CBLJSONMatcher* root = [CBLChangeMatcher changesFeedMatcherWithClient:
                            ^(id sequence, NSString *docID, NSArray *revs, bool deleted, bool removed) {
                                [docIDs addObject: docID];
                            }];
    CBLJSONReader* parser = [[CBLJSONReader alloc] initWithMatcher: root];
    CAssert([parser parseData: [kJSON dataUsingEncoding: NSUTF8StringEncoding]]);
    CAssert([parser finish]);
    CAssertEqual(docIDs, (@[@"1", @"10", @"100"]));
}
