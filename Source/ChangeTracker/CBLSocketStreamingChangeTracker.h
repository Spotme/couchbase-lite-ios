//
//  CBLSocketChangeTracker.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLChangeTracker.h"

@class CBLJSONReader;

/** CBLChangeTracker implementation that uses a raw TCP socket to read the chunk-mode HTTP response. */
@interface CBLSocketStreamingChangeTracker : CBLChangeTracker
{
    @private
    NSInputStream* _trackingInput;
    
    NSMutableData* _inputBuffer;
    NSMutableData* _changeBuffer;
    CFHTTPMessageRef _unauthResponse;
    NSURLCredential* _credential;
    CFAbsoluteTime _startTime;
    bool _gotResponseHeaders;
    bool _inputAvailable;
    bool _atEOF;
    CBLJSONReader* _parser;
}
@end
