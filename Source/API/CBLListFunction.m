//
//  CBLListFunction.m
//  CouchbaseLite
//
//  Created by Igor Evsukov on 7/28/13.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//

#import "CBLListFunction.h"
#import "CBLListFunction+Internal.h"
#import "CBLDatabase.h"
#import "CBL_Shared.h"
#import "CBLQuery.h"
#import "CBLFunctionResult.h"

@implementation CBLListFunction

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

@dynamic listFunctionBlock;
- (CBLListFunctionBlock) listFunctionBlock {
    CBLDatabase* db = _db;
    return [db.shared valueForType: @"listfunc" name: _name inDatabaseNamed: db.name];
}

- (void) setListFunctionBlock: (CBLListFunctionBlock)listFunctionBlock {
    Assert(listFunctionBlock);
    CBLDatabase* db = _db;
    [db.shared setValue: [listFunctionBlock copy]
                 forType: @"listfunc" name: _name inDatabaseNamed: db.name];
}

- (CBLFunctionResult*) runWithQueryEnumenator: (CBLQueryEnumerator *)queryEnumenator head: (NSDictionary*)head params: (NSDictionary*)params {
    LogTo(List, @"Executing list function %@ ...", _name);
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    
    CBLListFunctionGetRowBlock getRowBlock = ^CBLQueryRow*(){
        CBLQueryRow *row = [queryEnumenator nextRow];
        return row;
    };
    
    CBLFunctionResult *resut = self.listFunctionBlock(head, params, getRowBlock);

    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    LogTo(List, @"...Finished executing list function %@, took %3.3fsec", _name, (end - start));
    
    return resut;
}

- (CBLFunctionResult*) runWithRows: (NSArray*)rows head: (NSDictionary*)head params: (NSDictionary*)params {
    LogTo(List, @"Executing list function %@ ...", _name);
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    
    NSUInteger count = rows.count;
    __block NSUInteger idx = 0;
    CBLListFunctionGetRowBlock getRowBlock = ^CBLQueryRow*(){
        if (idx < count) {
            CBLQueryRow* row = rows[idx];
            ++idx;
            return row;
        } else {
            return nil;
        }
    };
    
    CBLFunctionResult *resut = self.listFunctionBlock(head, params, getRowBlock);
    
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    LogTo(List, @"...Finished executing list function %@, took %3.3fsec", _name, (end - start));
    
    return resut;
}

#pragma mark CBLListFunctionCompiler
static id<CBLListFunctionCompiler> sCompiler;
+ (void) setCompiler: (id<CBLListFunctionCompiler>)compiler {
    sCompiler = compiler;
}

+ (id<CBLListFunctionCompiler>) compiler {
    return sCompiler;
}


@end
