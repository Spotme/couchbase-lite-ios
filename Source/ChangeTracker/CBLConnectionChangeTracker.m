//
//  TDConnectionChangeTracker.m
//  TouchDB
//
//  Created by Jens Alfke on 12/1/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
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

#import "CBLConnectionChangeTracker.h"
#import "CBLAuthorizer.h"
#import "CBLRemoteRequest.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "MYURLUtils.h"
#import "CBL_Replicator.h"

@implementation CBLConnectionChangeTracker

- (BOOL) start {
    if(_connection)
        return NO;
    [super start];
    _inputBuffer = [[NSMutableData alloc] init];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: self.changesFeedURL];
    request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    //request.timeoutInterval = 6.02e23;
    
    // Add authorization:
    if (_authorizer) {
        [request setValue: [_authorizer authorizeURLRequest: request forRealm: nil]
                 forHTTPHeaderField: @"Authorization"];
    }

    // Add custom headers.
    [self.requestHeaders enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        [request setValue: value forHTTPHeaderField: key];
    }];
    
    _connection = [NSURLConnection connectionWithRequest: request delegate: self];
    _startTime = CFAbsoluteTimeGetCurrent();
    [_connection start];
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, request.URL);
    return YES;
}


- (void) clearConnection {
    _connection = nil;
    _inputBuffer = nil;
}


- (void) stopped {
    LogTo(ChangeTracker, @"%@: Stopped", self);
    [self clearConnection];
    [super stopped];
}


- (void) stop {
    if (_connection)
        [_connection cancel];
    [super stop];
}


- (bool) retryWithCredential {
    if (_authorizer || _challenged)
        return false;
    _challenged = YES;
    NSURLCredential* cred = [_databaseURL my_credentialForRealm: nil
                                           authenticationMethod: NSURLAuthenticationMethodHTTPBasic];
    if (!cred) {
        LogTo(ChangeTracker, @"Got 401 but no stored credential found (with nil realm)");
        return false;
    }

    [_connection cancel];
    self.authorizer = [[CBLBasicAuthorizer alloc] initWithCredential: cred];
    LogTo(ChangeTracker, @"Got 401 but retrying with %@", _authorizer);
    [self clearConnection];
    [self start];
    return true;
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    BOOL trusted = [_client changeTrackerApproveSSLTrust:challenge.protectionSpace.serverTrust
                                                 forHost:_databaseURL.host
                                                    port:(UInt16)_databaseURL.port.intValue];
    if (trusted) {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
            [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
        
        [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
    else {
        [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    CBLStatus status = (CBLStatus) ((NSHTTPURLResponse*)response).statusCode;
    LogTo(ChangeTracker, @"%@: Got response, status %d", self, status);
    if (status == 401) {
        // CouchDB says we're unauthorized but it didn't present a 'WWW-Authenticate' header
        // (it actually does this on purpose...) Let's see if we have a credential we can try:
        if ([self retryWithCredential])
            return;
    }
    if (CBLStatusIsError(status)) {
        Warn(@"%@: Got status %i for %@", self, status, _databaseURL);
        [self connection: connection
              didFailWithError: CBLStatusToNSError(status, self.changesFeedURL)];
    } else {
        _retryCount = 0;  // successful connection
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    LogTo(ChangeTrackerVerbose, @"%@: Got %lu bytes", self, (unsigned long)data.length);
    [_inputBuffer appendData: data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self clearConnection];
    [self failedWithError: error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    // Now parse the entire response as a JSON document:
    NSData* input = _inputBuffer;
    LogTo(ChangeTracker, @"%@: Got entire body, %u bytes", self, (unsigned)input.length);
    BOOL restart = NO;
    NSString* errorMessage = nil;
    NSInteger numChanges = [self receivedPollResponse: input errorMessage: &errorMessage];
    if (numChanges < 0) {
        // Oops, unparseable response:
        restart = [self checkInvalidResponse: input];
        if (!restart)
            [self setUpstreamError: errorMessage];
    }
    //else {
    //    // Poll again if there was no error, and either we're in longpoll mode or it looks like we
    //    // ran out of changes due to a _limit rather than because we hit the end.
    //    restart = _mode == kLongPoll || numChanges == (NSInteger)_limit;
    //}
    
    [self clearConnection];
    
    if (restart)
        [self start];       // Next poll...
    else
        [self stopped];
}

- (BOOL) checkInvalidResponse: (NSData*)body {
    NSString* bodyStr = [[body my_UTF8ToString] stringByTrimmingCharactersInSet:
                                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (_mode == kLongPoll && $equal(bodyStr, @"{\"results\":[")) {
        // Looks like the connection got closed by a proxy (like AWS' load balancer) before
        // the server had an actual change to send.
        NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _startTime;
        Warn(@"%@: Longpoll connection closed (by proxy?) after %.1f sec", self, elapsed);
        if (elapsed >= 30.0) {
            self.heartbeat = MIN(_heartbeat, elapsed * 0.75);
            return YES;  // should restart connection
        }
    } else if (bodyStr) {
        Warn(@"%@: Unparseable response:\n%@", self, bodyStr);
    } else {
        Warn(@"%@: Response is invalid UTF-8; as CP1252:\n%@", self,
             [[NSString alloc] initWithData: body encoding: NSWindowsCP1252StringEncoding]);
    }
    return NO;
}


@end
