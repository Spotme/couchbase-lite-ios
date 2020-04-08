//
//  CBLChangeTracker.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/20/11.
//  Copyright 2011-2013 Couchbase, Inc.
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

#import "CBLChangeTracker.h"
//#import "CBLSocketStreamingChangeTracker.h"
//#import "CBLConnectionChangeTracker.h"
//#import "CBLSocketChangeTracker.h"
#import "CBLAuthorizer.h"
#import "CBLMisc.h"
#import "CBLStatus.h"


#define kDefaultHeartbeat (5 * 60.0)

#define kInitialRetryDelay 2.0      // Initial retry delay (doubles after every subsequent failure)
#define kMaxRetryDelay (10*60.0)    // ...but will never get longer than this

@implementation CBLChangeTracker

@synthesize lastSequenceID=_lastSequenceID, databaseURL=_databaseURL, mode=_mode;
@synthesize limit=_limit, heartbeat=_heartbeat, error=_error, continuous=_continuous;
@synthesize client=_client, filterName=_filterName, filterParameters=_filterParameters;
@synthesize requestHeaders = _requestHeaders, authorizer=_authorizer;
@synthesize docIDs = _docIDs, pollInterval=_pollInterval;
@synthesize seqInterval = _seqInterval;

- (instancetype) initWithDatabaseURL: (NSURL*)databaseURL
                                mode: (CBLChangeTrackerMode)mode
                           conflicts: (BOOL)includeConflicts
                        lastSequence: (id)lastSequenceID
                              client: (id<CBLChangeTrackerClient>)client
{
    NSParameterAssert(databaseURL);
    NSParameterAssert(client);
    self = [super init];
    if (self) {
        if([self class] == [CBLChangeTracker class]) {
            // CBLChangeTracker is abstract; instantiate a concrete subclass instead.
            
            Class CBLSocketStreamingChangeTrackerClass = NSClassFromString(@"CBLSocketStreamingChangeTracker");
            if (CBLSocketStreamingChangeTrackerClass) {
                return [[CBLSocketStreamingChangeTrackerClass alloc] initWithDatabaseURL: databaseURL
                                                                                    mode: mode
                                                                               conflicts: includeConflicts
                                                                            lastSequence: lastSequenceID
                                                                                  client: client];
            }
            
            // NSURLConnection-base due the underlying implementation can only handle normal _change feed
            Class CBLConnectionChangeTrackerClass = NSClassFromString(@"CBLConnectionChangeTracker");
            if (mode == kOneShot && CBLConnectionChangeTrackerClass) {
                return [[CBLConnectionChangeTrackerClass alloc] initWithDatabaseURL: databaseURL
                                                                               mode: mode
                                                                          conflicts: includeConflicts
                                                                       lastSequence: lastSequenceID
                                                                             client: client];
            }
            
            // falling back to the latest available subclass CBLSocketChangeTracker
            Class CBLSocketChangeTrackerClass = NSClassFromString(@"CBLSocketChangeTracker");
            if (CBLSocketChangeTrackerClass) {
                return [[CBLSocketChangeTrackerClass alloc] initWithDatabaseURL: databaseURL
                                                                           mode: mode
                                                                      conflicts: includeConflicts
                                                                   lastSequence: lastSequenceID
                                                                         client: client];
            }
        }
        _databaseURL = databaseURL;
        _client = client;
        _mode = mode;
        _heartbeat = kDefaultHeartbeat;
        _includeConflicts = includeConflicts;
        _lastSequenceID = lastSequenceID;
    }
    return self;
}

- (NSString*) databaseName {
    return _databaseURL.path.lastPathComponent;
}

- (NSString*) changesFeedPath {
    static NSString* const kModeNames[3] = {@"normal", @"longpoll", @"continuous"};
    NSMutableString* path;
    path = [NSMutableString stringWithFormat: @"_changes?feed=%@&heartbeat=%.0f",
                                              kModeNames[_mode], _heartbeat*1000.0];
    if (_includeConflicts)
        [path appendString: @"&style=all_docs"];
    id seq = _lastSequenceID;
    if (seq) {
        // BigCouch is now using arrays as sequence IDs. These need to be sent back JSON-encoded.
        if ([seq isKindOfClass: [NSArray class]] || [seq isKindOfClass: [NSDictionary class]])
            seq = [CBLJSON stringWithJSONObject: seq options: 0 error: nil];
        [path appendFormat: @"&since=%@", CBLEscapeURLParam([seq description])];
    }
    if (_limit > 0)
        [path appendFormat: @"&limit=%u", _limit];

    // Add filter or doc_ids:
    NSString* filterName = _filterName;
    NSDictionary* filterParameters = _filterParameters;
    if (_docIDs) {
        filterName = @"_doc_ids";
        filterParameters = @{@"doc_ids": _docIDs};
    }
    if (filterName) {
        [path appendFormat: @"&filter=%@", CBLEscapeURLParam(filterName)];
        for (NSString* key in filterParameters) {
            NSString* value = filterParameters[key];
            if (![value isKindOfClass: [NSString class]]) {
                // It's ambiguous whether non-string filter params are allowed.
                // If we get one, encode it as JSON:
                NSError* error;
                value = [CBLJSON stringWithJSONObject: value options: CBLJSONWritingAllowFragments
                                                error: &error];
                if (!value) {
                    Warn(@"Illegal filter parameter %@ = %@", key, filterParameters[key]);
                    continue;
                }
            }
            [path appendFormat: @"&%@=%@", CBLEscapeURLParam(key),
                                           CBLEscapeURLParam(value)];
        }
    }
    
    // Add seq interval to skip calculating certain sequences
    if (_seqInterval && _seqInterval > 0) {
        [path appendFormat: @"&seq_interval=%u", _seqInterval];
    }

    return path;
}

- (NSURL*) changesFeedURL {
    return CBLAppendToURL(_databaseURL, self.changesFeedPath);
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%p %@]", [self class], self, self.databaseName];
}

- (void) dealloc {
    [self stop];
}

- (void) setUpstreamError: (NSString*)message {
    Warn(@"%@: Server error: %@", self, message);
    self.error = [NSError errorWithDomain: @"CBLChangeTracker" code: kCBLStatusUpstreamError userInfo: nil];
}

- (BOOL) start {
    self.error = nil;
    return NO;
}

- (void) stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(retry)
                                               object: nil];    // cancel pending retries
    [self stopped];
}

- (void) stopped {
    _retryCount = 0;
    // Clear client ref so its -changeTrackerStopped: won't be called again during -dealloc
    id<CBLChangeTrackerClient> client = _client;
    _client = nil;
    if ([client respondsToSelector: @selector(changeTrackerStopped:)])
        [client changeTrackerStopped: self];    // note: this method might release/dealloc me
}


- (void) failedWithError: (NSError*)error {
    // If the error may be transient (flaky network, server glitch), retry:
    if (!CBLIsPermanentError(error) && (_continuous || CBLMayBeTransientError(error))) {
        NSTimeInterval retryDelay = kInitialRetryDelay * (1 << MIN(_retryCount, 16U));
        retryDelay = MIN(retryDelay, kMaxRetryDelay);
        ++_retryCount;
        LogMY(@"%@: Connection error #%d, retrying in %.1f sec: %@",
            self, _retryCount, retryDelay, error.localizedDescription);
        [self retryAfterDelay: retryDelay];
    } else {
        Warn(@"%@: Can't connect, giving up: %@", self, error);
        self.error = error;
        [self stop];
    }
}


- (void) retryAfterDelay: (NSTimeInterval)retryDelay {
    [self performSelector: @selector(retry) withObject: nil afterDelay: retryDelay];
}


- (void) retry {
    if ([self start]) {
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(retry)
                                                   object: nil];    // cancel pending retries
    }
}

- (BOOL) receivedChanges: (NSArray*)changes errorMessage: (NSString**)errorMessage {
    [changes enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop){
        // being very careful on what we have received from _changes feed
        // no-one likes crashes in production
        
        NSDictionary* change = (NSDictionary*)obj;
        if (![change isKindOfClass: [NSDictionary class]])
            return;
        
        id sequence = [change objectForKey: @"seq"];
        
        NSString* docID = [change objectForKey: @"id"];
        if (!docID || ![docID isKindOfClass: [NSString class]])
            return;
        
        NSArray *changes = [change objectForKey: @"changes"];
        if (!changes || ![changes isKindOfClass: [NSArray class]])
            return;
        
        NSMutableArray* revIDs = [NSMutableArray new];
        [changes enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop){
            NSDictionary* change = (NSDictionary*)obj;
            if (![change isKindOfClass: [NSDictionary class]])
                return;
            
            NSString* revID = [change objectForKey: @"rev"];
            if (!revID || ![revID isKindOfClass: [NSString class]])
                return;
            
            [revIDs addObject: revID];
        }];
        
        BOOL deleted = NO;
        if ([[change objectForKey: @"deleted"] respondsToSelector: @selector(boolValue)])
            deleted = [[change objectForKey: @"deleted"] boolValue];
        
        BOOL removed = NO;
        if ([[change objectForKey: @"removed"] respondsToSelector: @selector(boolValue)])
            removed = [[change objectForKey: @"removed"] boolValue];
        
        [self.client changeTrackerReceivedSequence: sequence
                                             docID: docID
                                            revIDs: revIDs
                                           deleted: deleted
                                           removed: removed];
    }];
    
    return YES;
}

- (NSInteger) receivedPollResponse: (NSData*)body errorMessage: (NSString**)errorMessage {
    if (!body) {
        if (errorMessage)
            *errorMessage = @"No body in response";
        return -1;
    }
    NSError* error;
    id changeObj = [CBLJSON JSONObjectWithData: body options: 0 error: &error];
    if (!changeObj) {
        if (errorMessage)
            *errorMessage = $sprintf(@"JSON parse error: %@", error.localizedDescription);
        return -1;
    }
    NSDictionary* changeDict = $castIf(NSDictionary, changeObj);
    
    NSArray* changes = $castIf(NSArray, changeDict[@"results"]);
    if (!changes) {
        if (errorMessage)
            *errorMessage = @"No 'changes' array in response";
        return -1;
    }
    if (![self receivedChanges: changes errorMessage: errorMessage])
        return -1;
    
    NSString *lastSequence = $castIf(NSString, changeDict[@"last_seq"]);
    if (!lastSequence) {
        if (errorMessage)
            *errorMessage = @"No 'last_seq' field in response";
        return -1;
    }
    [self.client setLastSequence:lastSequence];
    
    return changes.count;
}

@end
