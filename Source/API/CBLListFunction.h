//
//  CBLListFunction.h
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

#import <Foundation/Foundation.h>
#import "CBLStatus.h"
@class CBLDatabase, CBLQueryRow, CBLQueryEnumerator, CBLFunctionResult;

#pragma mark - BLOCK DEFINITIONS
typedef CBLQueryRow* (^CBLListFunctionGetRowBlock)();

typedef CBLFunctionResult* (^CBLListFunctionBlock)(NSDictionary *head, NSDictionary *params, CBLListFunctionGetRowBlock getRowBlock);

#define LISTBLOCK(BLOCK) ^CBLFunctionResult*(NSDictionary *head, NSDictionary *params, CBLListFunctionGetRowBlock getRowBlock){BLOCK}

#pragma mark - LIST FUNCTION
/** A "list function" in a CouchbaseLite database -- essentially a stored function used to modify view output.
 List functions doesn't make much sense to use in native code, but very useful when declared in design document. */
@interface CBLListFunction : NSObject
{
    @private
    CBLDatabase* __weak _db;
    NSString *_name;

}

/** The database that owns this show function. */
@property (readonly) CBLDatabase* database;

/** The name of the show function.
 In case of JS function it will be ddoc/showfuncname */
@property (readonly) NSString* name;

/** The block that controls how view output it gets changed */
@property (readwrite) CBLListFunctionBlock listFunctionBlock;

- (CBLFunctionResult*) runWithQueryEnumenator: (CBLQueryEnumerator*)queryEnumenator head: (NSDictionary*)head params: (NSDictionary*)params;

/**
 * @rows array for CBLQueryRow objects
 */
- (CBLFunctionResult*) runWithRows: (NSArray*)rows head: (NSDictionary*)head params: (NSDictionary*)params;

@end
