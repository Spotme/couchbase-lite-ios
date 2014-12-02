//
//  CBLShowFunction.m
//  CouchbaseLite
//
//  Created by Igor Evsukov on 7/27/13.
//
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//


#import "CBLShowFunction.h"
#import "CBLShowFunction+Internal.h"
#import "CBL_Shared.h"
#import "CBLRevision.h"
#import "CBLFunctionResult.h"

@implementation CBLShowFunction

- (instancetype) initWithDatabase: (CBLDatabase*)db name: (NSString*)name {
    Assert(db);
    Assert(name.length);
    self = [super init];
    if (self) {
        _db = db;
        _name = [name copy];
    }
    return self;
}

#pragma mark properties
@synthesize name=_name;

- (CBLDatabase*) database {
    return _db;
}

@dynamic showFunctionBlock;
- (CBLShowFunctionBlock) showFunctionBlock {
    CBLDatabase *db = _db;
    return [db.shared valueForType: @"showfunc" name: _name inDatabaseNamed: db.name];
}

- (void)setShowFunctionBlock: (CBLShowFunctionBlock)showFunctionBlock {
    Assert(showFunctionBlock);
    CBLDatabase *db = _db;
    [db.shared setValue: [showFunctionBlock copy]
                 forType: @"showfunc" name: _name inDatabaseNamed: db.name];
}

#pragma mark invoking show function
- (CBLFunctionResult*) runWithRevision: (CBLRevision *)revision params: (NSDictionary *)params {
    NSDictionary *properties = revision.properties;
    return [self runWithRevisionProperties:properties params:params];
}

- (CBLFunctionResult*)runWithRevisionProperties: (NSDictionary *)revisionProperties params: (NSDictionary *)params {
    LogTo(Show, @"Executing show function %@ ...", _name);
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    
    CBLFunctionResult* result = self.showFunctionBlock(revisionProperties, params);
    
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    LogTo(Show, @"...Finished executing show function %@, took %3.3fsec", _name, (end - start));
    
    return result;
}

#pragma mark CBLShowFunctionCompiler
static id<CBLShowFunctionCompiler> sCompiler;
+ (void) setCompiler: (id<CBLShowFunctionCompiler>)compiler {
    sCompiler = compiler;
}

+ (id<CBLShowFunctionCompiler>) compiler {
    return sCompiler;
}

@end
